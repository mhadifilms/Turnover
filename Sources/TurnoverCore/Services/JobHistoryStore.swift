import Foundation

public final class JobHistoryStore: Sendable {
    private let fileURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("VFXUpload", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("job-history.json")
    }

    public func save(_ jobs: [PersistedJob]) {
        do {
            let data = try JSONEncoder().encode(jobs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[JobHistoryStore] Save failed: \(error)")
        }
    }

    public func load() -> [PersistedJob] {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([PersistedJob].self, from: data)
        } catch {
            return []
        }
    }
}
