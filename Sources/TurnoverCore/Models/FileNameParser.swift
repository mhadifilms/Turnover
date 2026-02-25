import Foundation

public struct ParsedFileName: Sendable, Equatable {
    public let projectName: String?  // e.g. "MyShow", nil when filename omits prefix
    public let episodeNumber: Int    // e.g. 201
    public let shotNumber: String    // e.g. "052"
    public let suffix: String        // e.g. "vfx"
    public let version: String       // e.g. "v001"
    public let frameNumber: String?  // e.g. "0001" for EXR sequences, nil for video
    public let fileExtension: String // e.g. "mov" or "exr"

    /// Prefix used to match shot folders: "MyShow_201_052" or "201_052"
    public var shotPrefix: String {
        if let projectName {
            return "\(projectName)_\(episodeNumber)_\(shotNumber)"
        }
        return "\(episodeNumber)_\(shotNumber)"
    }

    /// Base name without frame number: "MyShow_201_052_vfx_v001"
    public var sequenceBaseName: String {
        let prefix = projectName.map { "\($0)_" } ?? ""
        return "\(prefix)\(episodeNumber)_\(shotNumber)_\(suffix)_\(version)"
    }

    /// True if this file has a frame number (part of an image sequence)
    public var isSequenceFrame: Bool { frameNumber != nil }

    /// True if this is a video container that supports ffprobe/mux/color tagging
    public var isVideo: Bool {
        let ext = fileExtension.lowercased()
        return ["mov", "mp4", "m4v", "mxf", "avi", "mkv", "webm"].contains(ext)
    }
}

public enum FileNameParser {
    // Pattern: MyShow_201_052_vfx_v001.mov or 201_052_vfx_v001.0001.exr
    // Groups:  (Project_)?(Episode)_(Shot)_(suffix)_(version)(.(frame))?(ext)
    private static let pattern = #/^(?:(?<project>[A-Za-z]+)_)?(?<episode>\d{3})_(?<shot>\d{3})_(?<suffix>[A-Za-z0-9]+)_(?<version>[vV]\d+)(?:\.(?<frame>\d+))?\.(?<ext>\w+)$/#

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
            frameNumber: match.frame.map(String.init),
            fileExtension: String(match.ext)
        )
    }
}
