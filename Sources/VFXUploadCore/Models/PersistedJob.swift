import Foundation

public struct PersistedJob: Codable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let fileName: String
    public let s3DestinationPath: String
    public let colorSpaceRawValue: String
    public let status: PersistedStatus
    public let episodeNumber: Int?
    public let failureMessage: String?
    public let muxedFileURL: URL?
    public let taggedFileURL: URL?

    public enum PersistedStatus: String, Codable, Sendable {
        case pending, tagged, completed, failed
    }

    @MainActor
    public init(from job: UploadJob) {
        self.id = job.id
        self.sourceURL = job.sourceURL
        self.fileName = job.fileName
        self.s3DestinationPath = job.s3DestinationPath
        self.colorSpaceRawValue = job.colorSpace.rawValue
        self.episodeNumber = job.parsed?.episodeNumber

        self.muxedFileURL = job.muxedFileURL
        self.taggedFileURL = job.taggedFileURL

        switch job.status {
        case .completed:
            self.status = .completed
            self.failureMessage = nil
        case .tagged:
            self.status = .tagged
            self.failureMessage = nil
        case .failed(let msg):
            self.status = .failed
            self.failureMessage = msg
        default:
            // All in-progress states normalize to pending on restore
            self.status = .pending
            self.failureMessage = nil
        }
    }

    @MainActor
    public func toUploadJob() -> UploadJob {
        let job = UploadJob(sourceURL: sourceURL, id: id)

        // Restore project from episode number
        if let ep = episodeNumber, let project = ProjectCatalog.find(byEpisode: ep) {
            job.project = project
        }

        job.s3DestinationPath = s3DestinationPath
        job.colorSpace = ColorSpace(rawValue: colorSpaceRawValue) ?? .p3D65PQ

        // Restore temp file URLs if they still exist on disk
        if let url = muxedFileURL, FileManager.default.fileExists(atPath: url.path) {
            job.muxedFileURL = url
        }
        if let url = taggedFileURL, FileManager.default.fileExists(atPath: url.path) {
            job.taggedFileURL = url
        }

        switch status {
        case .completed:
            job.status = .completed
        case .tagged:
            // If no muxed/tagged temp file survived, re-tag is needed.
            // Re-tagging is fast and idempotent — safe even if file needs no changes.
            if job.muxedFileURL == nil && job.taggedFileURL == nil {
                job.status = .pending
            } else {
                job.status = .tagged
            }
        case .failed:
            job.status = .failed(failureMessage ?? "Unknown error")
        case .pending:
            job.status = .pending
        }

        return job
    }
}
