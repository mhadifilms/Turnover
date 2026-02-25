import Foundation

public struct Project: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let displayName: String
    public let s3Bucket: String
    public let s3BasePath: String
    public let episodeNumber: Int
    public let colorSpace: ColorSpace
    public let platesFolder: String
    public let vfxFolder: String

    public init(
        id: String, displayName: String, s3Bucket: String, s3BasePath: String,
        episodeNumber: Int, colorSpace: ColorSpace,
        platesFolder: String, vfxFolder: String
    ) {
        self.id = id
        self.displayName = displayName
        self.s3Bucket = s3Bucket
        self.s3BasePath = s3BasePath
        self.episodeNumber = episodeNumber
        self.colorSpace = colorSpace
        self.platesFolder = platesFolder
        self.vfxFolder = vfxFolder
    }
}

public enum ProjectStore {
    private static var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Turnover/projects.json")
    }

    public static func load() -> [Project] {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode([Project].self, from: data)
        } catch {
            return []
        }
    }

    public static func save(_ projects: [Project]) {
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(projects) else { return }
        try? data.write(to: configURL)
    }

    public static func importConfig(from url: URL) throws {
        let data = try Data(contentsOf: url)
        // Validate it decodes
        _ = try JSONDecoder().decode([Project].self, from: data)
        // Copy to config location
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: configURL.path) {
            try FileManager.default.removeItem(at: configURL)
        }
        try data.write(to: configURL)
    }

    public static func loadText() -> String {
        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    public static func saveText(_ text: String) throws {
        let data = Data(text.utf8)
        // Validate it decodes
        _ = try JSONDecoder().decode([Project].self, from: data)
        // Re-encode pretty-printed for consistent formatting
        let projects = try JSONDecoder().decode([Project].self, from: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let pretty = try encoder.encode(projects)
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try pretty.write(to: configURL)
    }

    public static func removeConfig() {
        try? FileManager.default.removeItem(at: configURL)
    }

    public static func find(byEpisode episode: Int) -> Project? {
        load().first { $0.episodeNumber == episode }
    }

    public static func find(byID id: String) -> Project? {
        load().first { $0.id == id }
    }
}
