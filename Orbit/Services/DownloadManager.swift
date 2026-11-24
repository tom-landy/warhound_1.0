import Foundation
import Observation
import SwiftData

/// Episode downloads on a background URLSession, so they carry on while the app is
/// suspended and pick up where they left off after the signal drops.
@MainActor
@Observable
final class DownloadManager: NSObject {
    static let shared = DownloadManager()
    static let sessionID = "com.tomlandy.Orbit.downloads"
    static let wifiOnlyKey = "downloadWifiOnly"
    static let removePlayedKey = "removePlayedDownloads"
    static let keepPerShowKey = "downloadsPerShow"
    static let maxRetries = 8

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
        case downloading(Double?)
        case downloaded
        case failed
    }

    /// Episode key -> fraction done, or -1 when waiting or the size is unknown.
    private(set) var active: [String: Double] = [:]
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
                guard let download = task as? URLSessionDownloadTask, let key = task.taskDescription else { continue }
                tasks[key] = download
                active[key] = -1
            }
        }
    }

    // MARK: - Queries

    func state(_ episode: Episode) -> State {
        if let p = active[episode.key] { return .downloading(p >= 0 ? p : nil) }
        if episode.isDownloaded { return .downloaded }
        if failed.contains(episode.key) { return .failed }
        return .none
    }

    // MARK: - Actions

    /// `automatic` downloads respect the Wi-Fi only setting. Ones you tap always go.
    func download(_ episode: Episode, automatic: Bool = false) {
        guard session != nil, !episode.isDownloaded, active[episode.key] == nil else { return }
        var request = URLRequest(url: episode.audioURL)
        request.setValue("Orbit/1.0", forHTTPHeaderField: "User-Agent")
        if automatic && UserDefaults.standard.bool(forKey: Self.wifiOnlyKey) {
            request.allowsCellularAccess = false
            request.allowsExpensiveNetworkAccess = false
            wifiOnly.insert(episode.key)
        } else {
            wifiOnly.remove(episode.key)
        }
        retries[episode.key] = 0
        start(session.downloadTask(with: request), key: episode.key)
    }

    func cancel(_ episode: Episode) {
        tasks[episode.key]?.cancel()
        clear(episode.key)
    }

    /// Restarts a Wi-Fi-only download so it goes over mobile data now.
    func downloadNow(_ episode: Episode) {
        cancel(episode)
        download(episode)
    }

    func remove(_ episode: Episode) {
        if let url = episode.localFileURL { try? FileManager.default.removeItem(at: url) }
        episode.localFileName = nil
        episode.downloadedAt = nil
        episode.fileSize = 0
        try? episode.modelContext?.save()
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
        guard context != nil else { return }
        let removePlayed = UserDefaults.standard.bool(forKey: Self.removePlayedKey)
        var keep = Set<String>()
        for episode in downloadedEpisodes() {
            guard let name = episode.localFileName,
                  FileManager.default.fileExists(atPath: Self.directory.appendingPathComponent(name).path) else {
                episode.localFileName = nil
                continue
            }
            if removePlayed && episode.isPlayed && episode.key != current?.key {
                remove(episode)
            } else {
                keep.insert(name)
            }
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        try? context?.save()
    }

    func downloadedEpisodes() -> [Episode] {
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.localFileName != nil })
        return (try? context?.fetch(descriptor)) ?? []
    }

    /// Screenshot support only.
    func showDemoProgress(_ key: String, _ fraction: Double) { active[key] = fraction }

    // MARK: - Internals

    private func start(_ task: URLSessionDownloadTask, key: String) {
        task.taskDescription = key
        tasks[key] = task
        active[key] = -1
        failed.remove(key)
        task.resume()
    }

    private func clear(_ key: String) {
        wifiOnly.remove(key)
        tasks[key] = nil
        active[key] = nil
        retries[key] = nil
    }

    fileprivate func progress(_ key: String, _ fraction: Double) {
        guard active[key] != nil else { return }
        // Only publish visible changes, so lists don't redraw on every packet.
        if fraction < 0 || abs((active[key] ?? 0) - fraction) >= 0.01 || fraction >= 1 {
            active[key] = fraction
        }
    }

    fileprivate func finished(_ key: String, fileName: String?, size: Int) {
        clear(key)
        guard let fileName else { failed.insert(key); return }
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.key == key })
        guard let episode = try? context?.fetch(descriptor).first else {
            try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(fileName))
            return
        }
        if let old = episode.localFileURL { try? FileManager.default.removeItem(at: old) }
        episode.localFileName = fileName
        episode.downloadedAt = .now
        episode.fileSize = size
        try? context?.save()
    }

    fileprivate func completed(_ key: String, task: URLSessionTask, error: Error?, resumeData: Data?) {
        guard tasks[key] === task || tasks[key] == nil else { return }
        guard let error else {
            if active[key] != nil { clear(key); failed.insert(key) }
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
        start(next, key: key)
        retries[key] = saved
        if heldForWifi { wifiOnly.insert(key) }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let key = downloadTask.taskDescription else { return }
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : -1
        MainActor.assumeIsolated { self.progress(key, fraction) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let key = downloadTask.taskDescription else { return }
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
            let name = UUID().uuidString + "." + ext.lowercased()
            let destination = Self.directory.appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                fileName = name
                size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            } catch {}
        }
        MainActor.assumeIsolated { self.finished(key, fileName: fileName, size: size) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let key = task.taskDescription else { return }
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
