import Foundation

public struct ParsedFileName: Sendable, Equatable {
    public let projectName: String?  // e.g. "MyShow", nil when filename omits prefix
    public let episodeNumber: Int    // e.g. 201
    public let shotNumber: String    // e.g. "052"
    public let suffix: String        // e.g. "vfx"
    public let version: String       // e.g. "v001"
    public let fileExtension: String // e.g. "mov"

    /// Prefix used to match shot folders: "MyShow_201_052" or "201_052"
    public var shotPrefix: String {
        if let projectName {
            return "\(projectName)_\(episodeNumber)_\(shotNumber)"
        }
        return "\(episodeNumber)_\(shotNumber)"
    }
}

public enum FileNameParser {
    // Pattern: MyShow_201_052_vfx_v001.mov or 201_052_vfx_v001.mov
    // Groups:  (Project_)?(Episode)_(Shot)_(suffix)_(version).(ext)
    private static let pattern = #/^(?:(?<project>[A-Za-z]+)_)?(?<episode>\d{3})_(?<shot>\d{3})_(?<suffix>[A-Za-z0-9]+)_(?<version>[vV]\d+)\.(?<ext>\w+)$/#

    public static func parse(fileName: String) -> ParsedFileName? {
        let name = URL(fileURLWithPath: fileName).lastPathComponent
        guard let match = try? pattern.wholeMatch(in: name) else { return nil }
        guard let episode = Int(match.episode) else { return nil }
        return ParsedFileName(
            projectName: match.project.map(String.init),
            episodeNumber: episode,
            shotNumber: String(match.shot),
            suffix: String(match.suffix),
            version: String(match.version),
            fileExtension: String(match.ext)
        )
    }
}
