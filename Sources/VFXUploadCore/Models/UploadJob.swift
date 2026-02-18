import Foundation

public enum UploadStatus: Sendable, Equatable {
    case pending
    case resolvingPath
    case muxingAudio
    case taggingColor
    case tagged
    case uploading(progress: Double)
    case completed
    case failed(String)

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }
}

@MainActor
public final class UploadJob: ObservableObject, Identifiable {
    public let id: UUID
    public let sourceURL: URL
    public let fileName: String
    public let parsed: ParsedFileName?

    @Published public var project: Project?
    @Published public var s3DestinationPath: String
    @Published public var colorSpace: ColorSpace
    @Published public var status: UploadStatus = .pending
    @Published public var isEditing: Bool = false
    /// If audio muxing produced a temp file, upload this instead
    public var muxedFileURL: URL?
    /// If color tagging produced a temp file, upload this instead
    public var taggedFileURL: URL?

    public var fileToUpload: URL { taggedFileURL ?? muxedFileURL ?? sourceURL }

    public var s3URI: String? {
        guard let project, !s3DestinationPath.isEmpty else { return nil }
        return "s3://\(project.s3Bucket)/\(s3DestinationPath)"
    }

    public init(sourceURL: URL, id: UUID = UUID()) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = sourceURL.lastPathComponent
        self.parsed = FileNameParser.parse(fileName: sourceURL.lastPathComponent)
        self.s3DestinationPath = ""
        self.colorSpace = .p3D65PQ

        if let parsed, let project = ProjectCatalog.find(byEpisode: parsed.episodeNumber) {
            self.project = project
            self.colorSpace = project.colorSpace
        }
    }
}
