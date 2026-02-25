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
    public var activeTask: Task<Void, Never>?

    public init(aws: AWSCLIService, resolver: S3PathResolver, audioMuxer: AudioMuxingService) {
        self.aws = aws
        self.resolver = resolver
        self.audioMuxer = audioMuxer
    }

    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isTagging = false
        isUploading = false
    }

    // MARK: - Tag All

    public func tagAll(jobs: [UploadJob], enableAudioMuxing: Bool = true) async {
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
                if Task.isCancelled { group.cancelAll(); break }

                while running < maxConcurrent && index < pendingJobs.count {
                    let job = pendingJobs[index]
                    index += 1
                    running += 1

                    group.addTask {
                        guard !Task.isCancelled else { return }
                        await Self.tagJob(job, audioMuxer: audioMuxer, enableAudioMuxing: enableAudioMuxing)
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
                if Task.isCancelled { group.cancelAll(); break }

                while running < maxConcurrent && index < taggedJobs.count {
                    let job = taggedJobs[index]
                    index += 1
                    running += 1

                    group.addTask {
                        guard !Task.isCancelled else { return }
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
        audioMuxer: AudioMuxingService,
        enableAudioMuxing: Bool
    ) async {
        let fileName = await MainActor.run { job.fileName }
        let isSequence = await MainActor.run { job.isSequence }
        let parsed = await MainActor.run { job.parsed }
        let isVideo = parsed?.isVideo ?? false

        // Non-video files (sequences, images, etc.) skip tagging — just mark as ready
        if isSequence || !isVideo {
            log("[Tag] \(fileName): non-video file — skipping tagging")
            await MainActor.run { job.status = .tagged }
            return
        }

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
        var didMux = false
        var muxError: String?
        if enableAudioMuxing {
            await MainActor.run { job.status = .muxingAudio("Probing file\u{2026}") }
            do {
                if let muxedURL = try await audioMuxer.muxAudioIfNeeded(
                    job: job,
                    probeResult: probeResult,
                    colorFlags: needsColorTag ? colorFlags : nil,
                    onStep: { step in await MainActor.run { job.status = .muxingAudio(step) } }
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
        } else {
            log("[Tag] \(fileName): audio mux disabled by user")
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

        log("[Tag] \(fileName): done → will upload \(fileToUpload.lastPathComponent)")
        await MainActor.run { job.status = .tagged }
    }

    /// Upload a tagged job to S3
    nonisolated private static func uploadJob(
        _ job: UploadJob,
        aws: AWSCLIService
    ) async {
        await MainActor.run { job.status = .uploading(progress: -1) }
        let isSequence = await MainActor.run { job.isSequence }

        if isSequence {
            await uploadSequence(job, aws: aws)
        } else {
            await uploadSingleFile(job, aws: aws)
        }
    }

    nonisolated private static func uploadSingleFile(
        _ job: UploadJob,
        aws: AWSCLIService
    ) async {
        let (project, fileToUpload, sourceURL, s3Path, colorSpace) = await MainActor.run {
            (job.project, job.fileToUpload, job.sourceURL, job.s3DestinationPath, job.colorSpace)
        }

        log("[Upload] \(fileToUpload.lastPathComponent) → s3://\(project?.s3Bucket ?? "?")/\(s3Path)")

        guard let project else {
            await MainActor.run { job.status = .failed("No project assigned") }
            return
        }

        // Atomic write: S3 returns 412 Precondition Failed if the key already exists
        do {
            try await aws.conditionalUploadS3(
                localPath: fileToUpload,
                bucket: project.s3Bucket,
                key: s3Path,
                metadata: ["color-space": colorSpace.rawValue]
            )

            await MainActor.run { job.status = .completed }
        } catch let error as ProcessError {
            if error.stderr.contains("PreconditionFailed") || error.stderr.contains("412") {
                await MainActor.run { job.status = .failed("Already exists on S3 — won't overwrite") }
            } else {
                await MainActor.run { job.status = .failed(error.localizedDescription) }
            }
        } catch {
            await MainActor.run { job.status = .failed(error.localizedDescription) }
        }
    }

    nonisolated private static func uploadSequence(
        _ job: UploadJob,
        aws: AWSCLIService
    ) async {
        let (project, sequenceURLs, s3BasePath) = await MainActor.run {
            (job.project, job.sequenceURLs, job.s3DestinationPath)
        }

        guard let project else {
            await MainActor.run { job.status = .failed("No project assigned") }
            return
        }

        let total = sequenceURLs.count
        log("[Upload] Sequence \(s3BasePath) — \(total) frames")

        for (index, frameURL) in sequenceURLs.enumerated() {
            let frameName = frameURL.lastPathComponent
            let s3Key = "\(s3BasePath)/\(frameName)"

            do {
                try await aws.conditionalUploadS3(
                    localPath: frameURL,
                    bucket: project.s3Bucket,
                    key: s3Key
                )
                let progress = Double(index + 1) / Double(total)
                await MainActor.run { job.status = .uploading(progress: progress) }
                log("[Upload] Frame \(index + 1)/\(total): \(frameName)")
            } catch let error as ProcessError {
                if error.stderr.contains("PreconditionFailed") || error.stderr.contains("412") {
                    await MainActor.run { job.status = .failed("Frame \(frameName) already exists on S3") }
                } else {
                    await MainActor.run { job.status = .failed("Frame \(frameName): \(error.localizedDescription)") }
                }
                return
            } catch {
                await MainActor.run { job.status = .failed("Frame \(frameName): \(error.localizedDescription)") }
                return
            }
        }

        log("[Upload] Sequence complete: \(total) frames uploaded")
        await MainActor.run { job.status = .completed }
    }
}
