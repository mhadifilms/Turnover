import Foundation

public actor S3PathResolver {
    private let aws: AWSCLIService
    /// Cache: episodeKey -> (folders, timestamp)
    private var folderCache: [String: (folders: [String], fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    public init(aws: AWSCLIService) {
        self.aws = aws
    }

    /// List shot folders for an episode's working directory and find the one matching the shot prefix.
    /// Returns the full S3 key for the VFX destination folder.
    public func resolve(job: UploadJob) async throws -> String {
        let parsed = await MainActor.run { job.parsed }
        let project = await MainActor.run { job.project }
        guard let parsed, let project else {
            throw ResolverError.cannotParse
        }

        let folders = try await listShotFolders(project: project)
        let prefixLower = parsed.shotPrefix.lowercased()
        guard let shotFolder = folders.first(where: {
            let lower = $0.lowercased()
            return lower.hasPrefix(prefixLower) || lower.contains("_\(prefixLower)")
        }) else {
            throw ResolverError.shotNotFound(parsed.shotPrefix)
        }

        // shotFolder looks like "MyShow_202_103_vubcritical/" or "MYSHOW_205_001_na/"
        let folder = shotFolder.hasSuffix("/") ? String(shotFolder.dropLast()) : shotFolder
        // Use the actual folder name from S3 for the path, but our filename for the uploaded file
        let destKey = "\(project.s3BasePath)/\(folder)/\(project.vfxFolder)/\(parsed.shotPrefix)_\(parsed.suffix)_\(parsed.version).\(parsed.fileExtension)"
        return destKey
    }

    /// Find WAV files in the shot's plates folder on S3.
    public func findPlatesAudio(project: Project, shotFolder: String) async throws -> [String] {
        let prefix = "\(project.s3BasePath)/\(shotFolder)/\(project.platesFolder)/"
        let items = try await aws.listS3(bucket: project.s3Bucket, prefix: prefix)
        return items.filter { $0.lowercased().hasSuffix(".wav") }
    }

    /// Resolve the shot folder name for a parsed file.
    public func findShotFolder(project: Project, shotPrefix: String) async throws -> String {
        let folders = try await listShotFolders(project: project)
        let prefixLower = shotPrefix.lowercased()
        guard let match = folders.first(where: {
            let lower = $0.lowercased()
            return lower.hasPrefix(prefixLower) || lower.contains("_\(prefixLower)")
        }) else {
            throw ResolverError.shotNotFound(shotPrefix)
        }
        return match.hasSuffix("/") ? String(match.dropLast()) : match
    }

    // MARK: - Private

    private func listShotFolders(project: Project) async throws -> [String] {
        let key = project.id
        if let cached = folderCache[key], Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.folders
        }

        let prefix = "\(project.s3BasePath)/"
        let folders = try await aws.listS3(bucket: project.s3Bucket, prefix: prefix)
        folderCache[key] = (folders, Date())
        return folders
    }
}

public enum ResolverError: Error, LocalizedError {
    case cannotParse
    case shotNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .cannotParse: return "Could not parse filename"
        case .shotNotFound(let prefix): return "No shot folder matching '\(prefix)'"
        }
    }
}
