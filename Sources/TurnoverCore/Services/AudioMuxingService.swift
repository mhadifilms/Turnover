import Foundation

public actor AudioMuxingService {
    private let aws: AWSCLIService
    private let resolver: S3PathResolver

    public init(aws: AWSCLIService, resolver: S3PathResolver) {
        self.aws = aws
        self.resolver = resolver
    }

    // MARK: - Probe

    /// Single ffprobe call that returns audio presence + video color metadata.
    public func probeFile(fileURL: URL) async -> ProbeResult {
        let ffprobe = findExecutable("ffprobe")
        do {
            let (stdout, _) = try await runProcess(
                ffprobe,
                "-v", "quiet",
                "-show_entries", "stream=codec_type,color_primaries,color_transfer,color_space",
                "-of", "json",
                fileURL.path
            )

            guard let data = stdout.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streams = json["streams"] as? [[String: Any]]
            else {
                return ProbeResult(hasAudioTrack: true, colorPrimaries: nil, colorTransfer: nil, colorSpace: nil)
            }

            let hasAudio = streams.contains { ($0["codec_type"] as? String) == "audio" }

            // Get color info from the first video stream
            var primaries: String?
            var transfer: String?
            var space: String?
            if let videoStream = streams.first(where: { ($0["codec_type"] as? String) == "video" }) {
                primaries = videoStream["color_primaries"] as? String
                transfer = videoStream["color_transfer"] as? String
                space = videoStream["color_space"] as? String
            }

            return ProbeResult(
                hasAudioTrack: hasAudio,
                colorPrimaries: primaries,
                colorTransfer: transfer,
                colorSpace: space
            )
        } catch {
            // Assume has audio if we can't probe
            return ProbeResult(hasAudioTrack: true, colorPrimaries: nil, colorTransfer: nil, colorSpace: nil)
        }
    }

    // MARK: - Audio Mux

    /// Download audio from S3 plates folder, mux with video, return path to muxed file.
    /// When colorFlags is non-nil, piggybacks color tagging onto the same ffmpeg call.
    public func muxAudioIfNeeded(job: UploadJob, probeResult: ProbeResult, colorFlags: [String]?) async throws -> URL? {
        let (sourceURL, project, parsed) = await MainActor.run { (job.sourceURL, job.project, job.parsed) }

        guard let project, let parsed else { return nil }

        // Skip if video already has audio
        if probeResult.hasAudioTrack { return nil }

        // Find shot folder
        let shotFolder: String
        do {
            shotFolder = try await resolver.findShotFolder(project: project, shotPrefix: parsed.shotPrefix)
        } catch {
            throw MuxError.wrap("Finding shot folder", error)
        }

        // Find WAVs in plates folder
        let wavFiles: [String]
        do {
            wavFiles = try await resolver.findPlatesAudio(project: project, shotFolder: shotFolder)
        } catch {
            throw MuxError.wrap("Listing audio stems", error)
        }
        guard !wavFiles.isEmpty else { return nil }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("turnover-mux-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            throw MuxError.diskError("Cannot create temp directory: \(error.localizedDescription)")
        }

        let ffmpeg = findExecutable("ffmpeg")
        let localAudio: URL

        // If there's a merged stem, use it directly. Otherwise download all stems and mix them.
        if let mergedWav = wavFiles.first(where: { $0.lowercased().contains("merged") }) {
            let safeName = URL(fileURLWithPath: mergedWav).lastPathComponent
            let wavKey = "\(project.s3BasePath)/\(shotFolder)/\(project.platesFolder)/\(mergedWav)"
            localAudio = tempDir.appendingPathComponent(safeName)
            do {
                try await aws.downloadS3(bucket: project.s3Bucket, key: wavKey, to: localAudio)
            } catch {
                throw MuxError.wrap("Downloading audio from S3", error)
            }
        } else {
            // Download all stems and merge with ffmpeg amix
            var localWavs: [URL] = []
            for wav in wavFiles {
                let safeName = URL(fileURLWithPath: wav).lastPathComponent
                let wavKey = "\(project.s3BasePath)/\(shotFolder)/\(project.platesFolder)/\(wav)"
                let localWav = tempDir.appendingPathComponent(safeName)
                do {
                    try await aws.downloadS3(bucket: project.s3Bucket, key: wavKey, to: localWav)
                } catch {
                    throw MuxError.wrap("Downloading \(safeName)", error)
                }
                localWavs.append(localWav)
            }

            localAudio = tempDir.appendingPathComponent("merged.wav")
            var mergeArgs = [ffmpeg]
            for wav in localWavs {
                mergeArgs += ["-i", wav.path]
            }
            mergeArgs += [
                "-filter_complex", "amix=inputs=\(localWavs.count):normalize=0",
                "-ac", "2",
                "-y", localAudio.path
            ]
            do {
                let _ = try await runProcess(mergeArgs)
            } catch {
                throw MuxError.wrap("Merging audio stems", error)
            }
        }

        // Mux video + audio — save next to the original with _review suffix
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let outputURL = sourceURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_review.\(ext)")

        var muxArgs = [
            ffmpeg,
            "-i", sourceURL.path,
            "-i", localAudio.path,
            "-c:v", "copy",
            "-c:a", "aac",
            "-shortest",
        ]
        // Piggyback color flags onto the mux if needed
        if let colorFlags {
            muxArgs += colorFlags
        }
        muxArgs += ["-y", outputURL.path]

        do {
            let _ = try await runProcess(muxArgs)
        } catch {
            throw MuxError.wrap("Muxing audio", error)
        }

        // Clean up temp downloads
        try? FileManager.default.removeItem(at: tempDir)

        return outputURL
    }

    // MARK: - Color Tagging

    /// Standalone color tagging when audio mux did NOT happen but color tagging IS needed.
    /// Pure container remux — zero re-encoding.
    public func tagColorSpaceIfNeeded(sourceURL: URL, probeResult: ProbeResult, targetColorSpace: ColorSpace) async throws -> URL? {
        guard let colorFlags = targetColorSpace.ffmpegColorFlags,
              !probeResult.alreadyTagged(as: targetColorSpace)
        else { return nil }

        let ffmpeg = findExecutable("ffmpeg")
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let outputURL = sourceURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_review.\(ext)")

        var args = [
            ffmpeg,
            "-i", sourceURL.path,
            "-c:v", "copy",
            "-c:a", "copy",
        ]
        args += colorFlags
        args += ["-y", outputURL.path]

        let _ = try await runProcess(args)

        return outputURL
    }

    // MARK: - Private

    private func findExecutable(_ name: String) -> String {
        DependencyCheck.findExecutable(name) ?? name
    }

    private func runProcess(_ args: String...) async throws -> (stdout: String, stderr: String) {
        try await runProcess(args)
    }

    /// Run process on a real background thread, drain pipes concurrently to avoid deadlock.
    private func runProcess(_ args: [String], timeoutSeconds: Int = 300) async throws -> (stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(stdout: String, stderr: String), Error>) in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: args[0])
                process.arguments = Array(args.dropFirst())

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                var stdoutData = Data()
                var stderrData = Data()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global().async {
                    stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.enter()
                DispatchQueue.global().async {
                    stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                let semaphore = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    semaphore.signal()
                }
                let result = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds))
                if result == .timedOut {
                    process.terminate()
                    group.wait()
                    continuation.resume(throwing: ProcessError(exitCode: -1, stderr: "Process timed out after \(timeoutSeconds)s"))
                    return
                }

                group.wait()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: (stdout, stderr))
                } else {
                    continuation.resume(throwing: ProcessError(exitCode: process.terminationStatus, stderr: stderr))
                }
            }
        }
    }
}

enum MuxError: Error, LocalizedError {
    case diskError(String)
    case stepFailed(step: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .diskError(let msg): return msg
        case .stepFailed(let step, let detail): return "\(step): \(detail)"
        }
    }

    /// Wrap a caught error with a human-readable step name, condensing verbose stderr.
    static func wrap(_ step: String, _ error: Error) -> MuxError {
        let raw = error.localizedDescription
        // Condense common patterns
        if raw.contains("timed out") {
            return .stepFailed(step: step, detail: "Timed out")
        }
        if raw.contains("No space left") || raw.contains("Disk full") || raw.contains("ENOSPC") {
            return .stepFailed(step: step, detail: "Disk full")
        }
        if raw.contains("Could not resolve host") || raw.contains("Network is unreachable")
            || raw.contains("Connection refused") || raw.contains("Unable to locate credentials") {
            return .stepFailed(step: step, detail: "Network or credentials error")
        }
        if raw.contains("No such file") || raw.contains("does not exist") {
            return .stepFailed(step: step, detail: "File not found")
        }
        if raw.contains("Permission denied") || raw.contains("AccessDenied") {
            return .stepFailed(step: step, detail: "Permission denied")
        }
        // Truncate verbose ffmpeg/aws output to first meaningful line
        let firstLine = raw.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? Substring(raw)
        let truncated = firstLine.count > 120 ? firstLine.prefix(120) + "…" : firstLine
        return .stepFailed(step: step, detail: String(truncated))
    }
}
