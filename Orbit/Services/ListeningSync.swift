import CloudKit
import CryptoKit
import Foundation
import Observation
import SwiftData

/// The local SwiftData library stays authoritative for UI and offline playback.
@MainActor
@Observable
final class ListeningSync {
    static let shared = ListeningSync()
    static let enabledKey = "listeningSyncEnabled"

    private typealias Revision = ListeningSyncRevision
    private typealias Change = ListeningSyncRevision.Change

    private struct Journal: Codable {
        var account: String?
        var seeded = false
        var pending: [String: Revision] = [:]
    }

    enum Status: Equatable {
        case idle, syncing, synced, unavailable, differentAccount, retrying
    }

    private(set) var status = Status.idle
    @ObservationIgnored private var journal: Journal?
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var differentAccount = false
    @ObservationIgnored private var token: CKServerChangeToken?
    @ObservationIgnored private var zoneReady = false
    @ObservationIgnored private var remote: [String: (revision: Revision, record: CKRecord)] = [:]
    @ObservationIgnored private var applied: [String: String] = [:]
    @ObservationIgnored private var feedRetryAfter: [URL: Date] = [:]
    private let zoneID = CKRecordZone.ID(zoneName: "OrbitListening", ownerName: CKCurrentUserDefaultName)
    private let recordType = "ListeningState"
    private let payload = "encryptedPayload"

    private var enabled: Bool {
        !DemoData.isActive && UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    private var journalURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("OrbitListeningSync.json")
    }

    func recordSubscription(_ podcast: Podcast) {
        record([.subscription(feed: podcast.feedURL, followed: podcast.isSubscribed)])
    }

    func recordPlayback(_ episodes: [Episode]) {
        record(episodes.map { .playback(key: $0.key, position: $0.playbackPosition, played: $0.isPlayed) })
    }

    func recordPlaylist(_ playlist: SmartPlaylist?, id: UUID) {
        record([.playlist(id: id, value: playlist)])
    }

    private func record(_ changes: [Change]) {
        guard !DemoData.isActive, !differentAccount, !changes.isEmpty else { return }
        do {
            var journal = try loadJournal()
            guard enabled || journal.account != nil else { return }
            let now = Date.now
            for change in changes {
                journal.pending[change.key] = Revision(id: UUID().uuidString, date: now, change: change)
            }
            try save(journal)
            schedule()
        } catch {
            status = .retrying
        }
    }

    func schedule() {
        guard enabled, scheduled == nil else { return }
        scheduled = Task {
            try? await Task.sleep(for: .seconds(3))
            scheduled = nil
            await sync()
        }
    }

    func sync() async {
        guard enabled, !isSyncing, let context = AppEnvironment.container?.mainContext,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        isSyncing = true
        status = .syncing
        defer { isSyncing = false }

        let cloud = CKContainer(identifier: "iCloud." + bundleID)
        do {
            guard try await cloud.accountStatus() == .available else {
                status = .unavailable
                return
            }
            let account = try await cloud.userRecordID().recordName
            guard enabled else { return }
            var journal = try loadJournal()
            differentAccount = journal.account != nil && journal.account != account
            guard !differentAccount else {
                status = .differentAccount
                return
            }
            if journal.account == nil {
                journal.account = account
                try save(journal)
            }

            let database = cloud.privateCloudDatabase
            if !zoneReady {
                do {
                    _ = try await database.recordZone(for: zoneID)
                } catch let error as CKError where [.zoneNotFound, .unknownItem].contains(error.code) {
                    _ = try await database.save(CKRecordZone(zoneID: zoneID))
                }
                zoneReady = true
            }
            try await pull(from: database)
            guard enabled else { return }
            try seedIfNeeded(context)
            try await applyRemote(in: context)
            guard enabled else { return }
            try await push(to: database)
            status = .synced
        } catch let error as CKError where [.zoneNotFound, .changeTokenExpired].contains(error.code) {
            zoneReady = false
            token = nil
            remote.removeAll()
            applied.removeAll()
            status = .retrying
        } catch {
            status = .retrying
        }
    }

    private func loadJournal() throws -> Journal {
        if let journal { return journal }
        do {
            let loaded = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
            journal = loaded
            return loaded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Journal()
        }
    }

    private func save(_ journal: Journal) throws {
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: journalURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        self.journal = journal
    }

    private func seedIfNeeded(_ context: ModelContext) throws {
        var journal = try loadJournal()
        guard !journal.seeded else { return }
        let shows = try context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed }))
        let episodes = try context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.isPlayed || $0.playbackPosition > 0 }))
        var initial = shows.map { Change.subscription(feed: $0.feedURL, followed: true) }
        initial += episodes.map { .playback(key: $0.key, position: $0.playbackPosition, played: $0.isPlayed) }
        initial += SmartPlaylists.shared.items.map { .playlist(id: $0.id, value: $0) }
        for change in initial where journal.pending[change.key] == nil && remote[change.key] == nil {
            journal.pending[change.key] = Revision(id: UUID().uuidString, date: .distantPast, change: change)
        }
        journal.seeded = true
        try save(journal)
    }

    private func pull(from database: CKDatabase) async throws {
        var moreComing: Bool
        repeat {
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            guard enabled else { return }
            for result in page.modificationResultsByID.values {
                let record = try result.get().record
                guard record.recordType == recordType, let data = record.encryptedValues[payload] as? Data else { continue }
                let revision = try JSONDecoder().decode(Revision.self, from: data)
                remote[revision.change.key] = (revision, record)
            }
            if !page.deletions.isEmpty {
                let deleted = Set(page.deletions.map(\.recordID))
                remote = remote.filter { !deleted.contains($0.value.record.recordID) }
            }
            token = page.changeToken
            moreComing = page.moreComing
        } while moreComing
    }

    private func applyRemote(in context: ModelContext) async throws {
        // Follow shows first so feed episodes are available for incoming listening state.
        let revisions = remote.values.map(\.revision)
        let subscriptions = try revisions.filter { revision in
            guard case .subscription = revision.change else { return false }
            return try shouldApply(revision)
        }
        let podcasts = subscriptions.isEmpty ? [] : try context.fetch(FetchDescriptor<Podcast>())
        let byFeed = Dictionary(podcasts.map { ($0.feedURL, $0) }, uniquingKeysWith: { first, _ in first })
        for revision in subscriptions {
            guard case .subscription(let feed, let followed) = revision.change,
                  try shouldApply(revision) else { continue }
            if let existing = byFeed[feed] {
                applySubscription(followed, to: existing)
            } else if followed {
                guard (feedRetryAfter[feed] ?? .distantPast) <= .now else { continue }
                feedRetryAfter[feed] = .now.addingTimeInterval(300)
                let podcast: Podcast
                do {
                    podcast = try await FeedService.podcast(for: feed, context: context)
                } catch {
                    continue
                }
                guard try shouldApply(revision) else { continue }
                applySubscription(true, to: podcast)
            }
            try context.save()
            applied[revision.change.key] = revision.id
            SpotlightIndex.schedule(context: context)
        }
        let playback = try revisions.filter { revision in
            guard case .playback = revision.change else { return false }
            return try shouldApply(revision)
        }
        if !playback.isEmpty {
            let episodes = try context.fetch(FetchDescriptor<Episode>())
            let byKey = Dictionary(episodes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            var updated: [Revision] = []
            for revision in playback {
                guard case .playback(let key, let position, let played) = revision.change,
                      let episode = byKey[key],
                      AudioPlayer.shared.applySyncedPlayback(to: episode, position: position, played: played) else { continue }
                updated.append(revision)
            }
            try context.save()
            for revision in updated { applied[revision.change.key] = revision.id }
        }
        for revision in revisions {
            guard case .playlist(let id, let playlist) = revision.change, try shouldApply(revision) else { continue }
            SmartPlaylists.shared.apply(playlist, id: id)
            applied[revision.change.key] = revision.id
        }
    }

    private func shouldApply(_ revision: Revision) throws -> Bool {
        let key = revision.change.key
        guard enabled, applied[key] != revision.id else { return false }
        if let pending = try loadJournal().pending[key], pending.isNewer(than: revision) { return false }
        return true
    }

    private func applySubscription(_ followed: Bool, to podcast: Podcast) {
        guard podcast.isSubscribed != followed else { return }
        podcast.isSubscribed = followed
        podcast.subscribedAt = followed ? .now : nil
    }

    private func push(to database: CKDatabase) async throws {
        var journal = try loadJournal()
        var outgoing: [CKRecord.ID: Revision] = [:]
        var discarded = false
        var records: [CKRecord] = []
        for (key, revision) in journal.pending {
            if let saved = remote[key]?.revision, !revision.isNewer(than: saved) {
                journal.pending.removeValue(forKey: key)
                discarded = true
                continue
            }
            guard records.count < 100 else { continue }
            let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            let id = CKRecord.ID(recordName: hash, zoneID: zoneID)
            let record = remote[key]?.record ?? CKRecord(recordType: recordType, recordID: id)
            record.encryptedValues[payload] = try JSONEncoder().encode(revision) as NSData
            records.append(record)
            outgoing[id] = revision
        }
        if discarded { try save(journal) }
        guard !records.isEmpty, enabled else { return }

        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
        journal = try loadJournal()
        var failure: Error?
        for (id, revision) in outgoing {
            switch result.saveResults[id] {
            case .success(let record):
                let key = revision.change.key
                remote[key] = (revision, record)
                applied[key] = revision.id
                if journal.pending[key]?.id == revision.id { journal.pending.removeValue(forKey: key) }
            case .failure(let error):
                failure = error
            case nil:
                break
            }
        }
        try save(journal)
        if let failure { throw failure }
        if !journal.pending.isEmpty { schedule() }
    }
}
