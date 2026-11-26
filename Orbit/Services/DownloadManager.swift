import Foundation
import Observation
import SwiftData

/// Episode downloads on a background URLSession, so they carry on while the app is
/// suspended and pick up where they left off after the signal drops.
@MainActor
@Observable
final class DownloadManager: NSObject {
    static let shared = DownloadManager()
    static let sessionID = "com.warhound.orbit.downloads"
    static let wifiOnlyKey = "downloadWifiOnly"
    static let removePlayedKey = "removePlayedDownloads"
    static let keepPerShowKey = "downloadsPerShow"
    static let maxRetries = 8
    // Persist provenance in task descriptions and file names across app relaunches.
    // Existing tasks and files have no prefix and are kept as manual downloads.
    private nonisolated static let automaticPrefix = "automatic-"

    private nonisolated static func downloadKey(for task: URLSessionTask) -> String? {
        guard let description = task.taskDescription else { return nil }
        return description.hasPrefix(automaticPrefix)
            ? String(description.dropFirst(automaticPrefix.count))
            : description
    }

    /// Files live in Application Support, excluded from iCloud backup.
    nonisolated static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    /// Set by the app delegate when iOS wakes us to finish background downloads.
    static var backgroundCompletion: (() -> Void)?

    enum State: Equatable {
        case none
        case downloading
        case downloaded
        case failed
    }

    /// Episodes downloading or queued. Changes only when a download starts or stops, so lists
    /// don't redraw every row on each progress tick.
    private(set) var active: Set<String> = []
    /// Per-episode progress, observed only by that episode's progress ring.
    @ObservationIgnored private var progressByKey: [String: DownloadProgress] = [:]
    private(set) var failed: Set<String> = []
    /// Automatic downloads held back until Wi-Fi.
    private(set) var wifiOnly: Set<String> = []

    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var retries: [String: Int] = [:]
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var session: URLSession!

    func configure(context: ModelContext) {
        guard session == nil else { return }
        self.context = context
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        Task {
            // Reattach to downloads that were running when the app was last closed.
            for task in await session.allTasks {
                guard let download = task as? URLSessionDownloadTask,
                      download.state == .running || download.state == .suspended,
                      let key = Self.downloadKey(for: download), tasks[key] == nil else { continue }
                tasks[key] = download
                active.insert(key)
                if progressByKey[key] == nil { progressByKey[key] = DownloadProgress() }
            }
        }
    }

    // MARK: - Queries

    func state(_ episode: Episode) -> State {
        if active.contains(episode.key) { return .downloading }
        if episode.isDownloaded { return .downloaded }
        if failed.contains(episode.key) { return .failed }
        return .none
    }

    // MARK: - Actions

    /// `automatic` downloads respect the Wi-Fi only setting. Ones you tap always go.
    func download(_ episode: Episode, automatic: Bool = false, allowMobileData: Bool = false) {
        guard session != nil, !episode.isDownloaded, !active.contains(episode.key) else { return }
        var request = URLRequest(url: episode.audioURL)
        request.setValue("Orbit/1.0", forHTTPHeaderField: "User-Agent")
        if automatic && !allowMobileData && UserDefaults.standard.bool(forKey: Self.wifiOnlyKey) {
            request.allowsCellularAccess = false
            request.allowsExpensiveNetworkAccess = false
            wifiOnly.insert(episode.key)
        } else {
            wifiOnly.remove(episode.key)
        }
        retries[episode.key] = 0
        let task = session.downloadTask(with: request)
        task.taskDescription = automatic ? Self.automaticPrefix + episode.key : episode.key
        start(task, key: episode.key)
    }

    func cancel(_ episode: Episode) {
        if let task = tasks[episode.key] {
            task.taskDescription = nil
            task.cancel()
        }
        clear(episode.key)
    }

    /// Restarts a Wi-Fi-only download so it goes over mobile data now.
    func downloadNow(_ episode: Episode) {
        let automatic = tasks[episode.key]?.taskDescription?.hasPrefix(Self.automaticPrefix) == true
        cancel(episode)
        download(episode, automatic: automatic, allowMobileData: true)
    }

    func remove(_ episode: Episode) {
        if let url = episode.localFileURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                return
            }
        }
        episode.localFileName = nil
        episode.downloadedAt = nil
        episode.fileSize = 0
        try? episode.modelContext?.save()
    }

    func removeAutomaticDownload(_ episode: Episode) {
        if episode.localFileName?.hasPrefix(Self.automaticPrefix) == true {
            remove(episode)
        }
        if tasks[episode.key]?.taskDescription?.hasPrefix(Self.automaticPrefix) == true {
            cancel(episode)
        }
    }

    func removeAll() {
        for episode in downloadedEpisodes() { remove(episode) }
    }

    /// Called when an episode finishes or is marked played.
    func episodePlayed(_ episode: Episode) {
        if UserDefaults.standard.bool(forKey: Self.removePlayedKey) && episode.isDownloaded {
            remove(episode)
        }
    }

    /// Drops played downloads (if that setting is on), forgets missing files and deletes orphans.
    func cleanUp(keeping current: Episode? = nil) {
        guard let context, let episodes = try? fetchDownloadedEpisodes(in: context) else { return }
        let removePlayed = UserDefaults.standard.bool(forKey: Self.removePlayedKey)
        var keep = Set<String>()
        for episode in episodes {
            guard let name = episode.localFileName,
                  FileManager.default.fileExists(atPath: Self.directory.appendingPathComponent(name).path) else {
                episode.localFileName = nil
                continue
            }
            if removePlayed && episode.isPlayed && episode.key != current?.key {
                remove(episode)
            }
            if episode.localFileName != nil { keep.insert(name) }
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        try? context.save()
    }

    func downloadedEpisodes() -> [Episode] {
        guard let context else { return [] }
        return (try? fetchDownloadedEpisodes(in: context)) ?? []
    }

    private func fetchDownloadedEpisodes(in context: ModelContext) throws -> [Episode] {
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.localFileName != nil })
        return try context.fetch(descriptor)
    }

    /// Screenshot support only.
    func showDemoProgress(_ key: String, _ fraction: Double) {
        active.insert(key)
        let progress = DownloadProgress()
        progress.fraction = fraction >= 0 ? fraction : nil
        progressByKey[key] = progress
    }

    func progress(for key: String) -> DownloadProgress? { progressByKey[key] }

    // MARK: - Internals

    private func start(_ task: URLSessionDownloadTask, key: String) {
        tasks[key] = task
        active.insert(key)
        if progressByKey[key] == nil { progressByKey[key] = DownloadProgress() }
        failed.remove(key)
        task.resume()
    }

    private func clear(_ key: String) {
        wifiOnly.remove(key)
        tasks[key] = nil
        active.remove(key)
        progressByKey[key] = nil
        retries[key] = nil
    }

    fileprivate func progress(_ key: String, _ fraction: Double) {
        guard let progress = progressByKey[key] else { return }
        let new: Double? = fraction >= 0 ? fraction : nil
        // Only publish visible changes (whole percents).
        if new == nil || progress.fraction == nil || abs((progress.fraction ?? 0) - (new ?? 0)) >= 0.01 || (new ?? 0) >= 1 {
            progress.fraction = new
        }
    }

    fileprivate func finished(_ key: String, task: URLSessionDownloadTask, fileName: String?, size: Int) {
        guard tasks[key] === task || tasks[key] == nil else {
            if let fileName { try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(fileName)) }
            return
        }
        clear(key)
        guard let fileName else { failed.insert(key); return }
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.key == key })
        guard let episode = try? context?.fetch(descriptor).first else {
            try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(fileName))
            return
        }
        if let old = episode.localFileURL { try? FileManager.default.removeItem(at: old) }
        episode.localFileName = fileName
        // The downloaded file is the reliable place to read chapters from.
        if episode.chaptersData == nil { episode.chaptersChecked = false }
        episode.downloadedAt = .now
        episode.fileSize = size
        try? context?.save()
        AudioPlayer.shared.reloadChaptersIfNeeded(for: episode)
        if fileName.hasPrefix(Self.automaticPrefix),
           let podcast = episode.podcast, podcast.isSubscribed, podcast.autoDownload {
            FeedService.trimAutomaticDownloads(for: podcast)
        }
    }

    fileprivate func completed(_ key: String, task: URLSessionTask, error: Error?, resumeData: Data?) {
        guard tasks[key] === task || tasks[key] == nil else { return }
        guard let error else {
            if active.contains(key) { clear(key); failed.insert(key) }
            return
        }
        if (error as? URLError)?.code == .cancelled && resumeData == nil {
            clear(key)
            return
        }
        // Dropped connection: resume from where it stopped. The background session waits
        // for the network to come back before it actually retries.
        let attempt = (retries[key] ?? 0) + 1
        guard attempt <= Self.maxRetries else {
            clear(key)
            failed.insert(key)
            return
        }
        retries[key] = attempt
        let next: URLSessionDownloadTask
        if let resumeData {
            next = session.downloadTask(withResumeData: resumeData)
        } else if let request = task.originalRequest {
            next = session.downloadTask(with: request)
        } else {
            clear(key)
            failed.insert(key)
            return
        }
        let saved = retries[key]
        let heldForWifi = wifiOnly.contains(key)
        next.taskDescription = task.taskDescription
        start(next, key: key)
        retries[key] = saved
        if heldForWifi { wifiOnly.insert(key) }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let key = Self.downloadKey(for: downloadTask) else { return }
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : -1
        MainActor.assumeIsolated { self.progress(key, fraction) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let key = Self.downloadKey(for: downloadTask) else { return }
        // The temporary file is deleted when this method returns, so move it now.
        var fileName: String?
        var size = 0
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        if (200..<300).contains(status) {
            var ext = downloadTask.originalRequest?.url?.pathExtension ?? ""
            if ext.isEmpty || ext.count > 5 {
                ext = (downloadTask.response?.suggestedFilename as NSString?)?.pathExtension ?? ""
            }
            if ext.isEmpty || ext.count > 5 { ext = "mp3" }
            let prefix = downloadTask.taskDescription?.hasPrefix(Self.automaticPrefix) == true ? Self.automaticPrefix : ""
            let name = prefix + UUID().uuidString + "." + ext.lowercased()
            let destination = Self.directory.appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                fileName = name
                size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            } catch {}
        }
        MainActor.assumeIsolated { self.finished(key, task: downloadTask, fileName: fileName, size: size) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let key = Self.downloadKey(for: task) else { return }
        let resumeData = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        MainActor.assumeIsolated { self.completed(key, task: task, error: error, resumeData: resumeData) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            Self.backgroundCompletion?()
            Self.backgroundCompletion = nil
        }
    }
}

/// One download's progress: nil while waiting or when the size is unknown.
@MainActor
@Observable
final class DownloadProgress {
    var fraction: Double?
}
