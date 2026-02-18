import Foundation
import Combine

private func log(_ message: String) {
    var msg = message + "\n"
    msg.withUTF8 { buf in
        _ = fwrite(buf.baseAddress, 1, buf.count, stderr)
        fflush(stderr)
    }
}

@MainActor
public final class UploadManager: ObservableObject {
    @Published public var isTagging = false
    @Published public var isUploading = false
    @Published public var completedCount = 0
    @Published public var totalCount = 0

    private let aws: AWSCLIService
    private let resolver: S3PathResolver
    private let audioMuxer: AudioMuxingService
    private let maxConcurrent = 3

    public init(aws: AWSCLIService, resolver: S3PathResolver, audioMuxer: AudioMuxingService) {
        self.aws = aws
        self.resolver = resolver
        self.audioMuxer = audioMuxer
    }

    // MARK: - Tag All

    public func tagAll(jobs: [UploadJob]) async {
        let pendingJobs = jobs.filter {
            if case .pending = $0.status, !$0.s3DestinationPath.isEmpty { return true }
            return false
        }
        guard !pendingJobs.isEmpty else { return }

        isTagging = true
        totalCount = pendingJobs.count
        completedCount = 0

        let audioMuxer = self.audioMuxer

        await withTaskGroup(of: Void.self) { group in
            var running = 0
            var index = 0

            while index < pendingJobs.count || running > 0 {
                while running < maxConcurrent && index < pendingJobs.count {
                    let job = pendingJobs[index]
                    index += 1
                    running += 1

                    group.addTask {
                        await Self.tagJob(job, audioMuxer: audioMuxer)
                    }
                }

                if running > 0 {
                    await group.next()
                    running -= 1
                    self.completedCount += 1
                }
            }
        }

        isTagging = false
    }

    // MARK: - Upload All

    public func uploadAll(jobs: [UploadJob]) async {
        let taggedJobs = jobs.filter {
            if case .tagged = $0.status { return true }
            return false
        }
        guard !taggedJobs.isEmpty else { return }

        isUploading = true
        totalCount = taggedJobs.count
        completedCount = 0

        let aws = self.aws

        await withTaskGroup(of: Void.self) { group in
            var running = 0
            var index = 0

            while index < taggedJobs.count || running > 0 {
                while running < maxConcurrent && index < taggedJobs.count {
                    let job = taggedJobs[index]
                    index += 1
                    running += 1

                    group.addTask {
                        await Self.uploadJob(job, aws: aws)
                    }
                }

                if running > 0 {
                    await group.next()
                    running -= 1
                    self.completedCount += 1
                }
            }
        }

        isUploading = false
    }

    /// Resolve path for a single job without uploading.
    public func resolvePath(for job: UploadJob) async {
        job.status = .resolvingPath
        do {
            let destKey = try await resolver.resolve(job: job)
            job.s3DestinationPath = destKey
            job.status = .pending
        } catch {
            job.s3DestinationPath = ""
            job.status = .failed("Path resolution: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    /// Probe + audio mux + color tag, then set status to .tagged
    nonisolated private static func tagJob(
        _ job: UploadJob,
        audioMuxer: AudioMuxingService
    ) async {
        let fileName = await MainActor.run { job.fileName }

        // 1. Probe file (ONE ffprobe call)
        let sourceURL = await MainActor.run { job.sourceURL }
        let probeResult = await audioMuxer.probeFile(fileURL: sourceURL)
        log("[Tag] \(fileName): probe → hasAudio=\(probeResult.hasAudioTrack), color=\(probeResult.colorPrimaries ?? "nil")/\(probeResult.colorTransfer ?? "nil")/\(probeResult.colorSpace ?? "nil")")

        // 2. Determine if color tagging is needed
        let colorSpace = await MainActor.run { job.colorSpace }
        let colorFlags = colorSpace.ffmpegColorFlags
        let needsColorTag = colorFlags != nil && !probeResult.alreadyTagged(as: colorSpace)
        log("[Tag] \(fileName): needsColorTag=\(needsColorTag), targetColorSpace=\(colorSpace.rawValue)")

        // 3. Audio mux (piggybacks color flags if both needed)
        await MainActor.run { job.status = .muxingAudio }
        var didMux = false
        var muxError: String?
        do {
            if let muxedURL = try await audioMuxer.muxAudioIfNeeded(
                job: job,
                probeResult: probeResult,
                colorFlags: needsColorTag ? colorFlags : nil
            ) {
                await MainActor.run { job.muxedFileURL = muxedURL }
                didMux = true
                log("[Tag] \(fileName): muxed → \(muxedURL.lastPathComponent)")
            } else {
                log("[Tag] \(fileName): mux skipped (returned nil)")
            }
        } catch {
            muxError = error.localizedDescription
            log("[Tag] \(fileName): mux FAILED → \(error.localizedDescription)")
            await MainActor.run { job.muxedFileURL = nil }
        }

        // 4. Standalone color tagging if needed and audio mux didn't happen
        var tagError: String?
        if needsColorTag && !didMux {
            await MainActor.run { job.status = .taggingColor }
            do {
                if let taggedURL = try await audioMuxer.tagColorSpaceIfNeeded(
                    sourceURL: sourceURL,
                    probeResult: probeResult,
                    targetColorSpace: colorSpace
                ) {
                    await MainActor.run { job.taggedFileURL = taggedURL }
                    log("[Tag] \(fileName): color tagged → \(taggedURL.lastPathComponent)")
                } else {
                    log("[Tag] \(fileName): color tag skipped (returned nil)")
                }
            } catch {
                tagError = error.localizedDescription
                log("[Tag] \(fileName): color tag FAILED → \(error.localizedDescription)")
                await MainActor.run { job.taggedFileURL = nil }
            }
        }

        // 5. Check results — fail if errors occurred and no output was produced
        let fileToUpload = await MainActor.run { job.fileToUpload }
        let isOriginal = fileToUpload == sourceURL

        if isOriginal, let err = muxError ?? tagError {
            await MainActor.run { job.status = .failed("Tag failed: \(err)") }
            return
        }

        // 6. Update S3 key to match the actual file being uploaded
        if !isOriginal {
            await MainActor.run {
                let components = job.s3DestinationPath.split(separator: "/", omittingEmptySubsequences: false)
                let newKey = components.dropLast().joined(separator: "/") + "/" + fileToUpload.lastPathComponent
                job.s3DestinationPath = newKey
            }
        }

        log("[Tag] \(fileName): done → will upload \(fileToUpload.lastPathComponent)")
        await MainActor.run { job.status = .tagged }
    }

    /// Upload a tagged job to S3
    nonisolated private static func uploadJob(
        _ job: UploadJob,
        aws: AWSCLIService
    ) async {
        await MainActor.run { job.status = .uploading(progress: 0) }
        let (project, fileToUpload, s3Path, colorSpace) = await MainActor.run {
            (job.project, job.fileToUpload, job.s3DestinationPath, job.colorSpace)
        }

        log("[Upload] \(fileToUpload.lastPathComponent) → s3://\(project?.s3Bucket ?? "?")/\(s3Path)")

        guard let project else {
            await MainActor.run { job.status = .failed("No project assigned") }
            return
        }

        do {
            try await aws.uploadS3(
                localPath: fileToUpload,
                bucket: project.s3Bucket,
                key: s3Path,
                metadata: ["color-space": colorSpace.rawValue]
            ) { progress in
                Task { @MainActor in
                    job.status = .uploading(progress: progress)
                }
            }
            await MainActor.run { job.status = .completed }
        } catch {
            await MainActor.run { job.status = .failed(error.localizedDescription) }
        }
    }
}
