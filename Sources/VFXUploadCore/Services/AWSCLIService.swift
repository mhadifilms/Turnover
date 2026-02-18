import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum AWSCredentialStatus: Sendable, Equatable {
    case valid(account: String)
    case expired
    case notConfigured
    case error(String)
}

/// Not an actor - `profile` is immutable and there's no shared mutable state.
/// Using a class avoids serializing all S3 calls through one executor.
public final class AWSCLIService: Sendable {
    private let profile: String

    public init(profile: String = "default") {
        self.profile = profile
    }

    // MARK: - Credential Management

    public func checkCredentials() async -> AWSCredentialStatus {
        do {
            let (stdout, _) = try await run("aws", "sts", "get-caller-identity", "--profile", profile, "--output", "json")
            if let data = stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let account = json["Account"] as? String {
                return .valid(account: account)
            }
            return .valid(account: "unknown")
        } catch let error as ProcessError {
            if error.stderr.contains("expired") || error.stderr.contains("token") {
                return .expired
            }
            if error.stderr.contains("configure") || error.stderr.contains("NoCredential") {
                return .notConfigured
            }
            return .error(error.stderr)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Opens the SSO login URL in the default browser via `aws sso login`.
    /// This command is interactive — it needs stdout/stdin connected to handle the browser flow.
    public func ssoLogin() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["aws", "sso", "login", "--profile", profile]
        // Let stdin/stdout/stderr inherit so the browser URL gets opened
        process.standardInput = FileHandle.nullDevice
        // Capture stderr to detect the verification URL
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()

        // Read stderr on a background thread to find the verification URL
        let stderrHandle = stderrPipe.fileHandleForReading
        Task.detached {
            while true {
                let data = stderrHandle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8),
                   let urlRange = text.range(of: #"https://\S+"#, options: .regularExpression) {
                    let urlString = String(text[urlRange])
                    if let url = URL(string: urlString) {
                        let _ = await MainActor.run {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }

        // Wait for the process on a background thread (not cooperative pool)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ProcessError(exitCode: process.terminationStatus, stderr: "SSO login failed"))
                }
            }
        }
    }

    // MARK: - S3 Operations

    public func listS3(bucket: String, prefix: String) async throws -> [String] {
        let path = "s3://\(bucket)/\(prefix)"
        let (stdout, _) = try await run("aws", "s3", "ls", path, "--profile", profile)
        return stdout.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }
            // Directories: "PRE dirname/"
            if trimmed.hasPrefix("PRE ") {
                return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }
            // Files: "2024-01-01 12:00:00 1234 filename"
            let parts = trimmed.split(separator: " ", maxSplits: 3)
            if parts.count >= 4 { return String(parts[3]) }
            return nil
        }
    }

    public func downloadS3(bucket: String, key: String, to localPath: URL) async throws {
        let s3Path = "s3://\(bucket)/\(key)"
        let _ = try await run("aws", "s3", "cp", s3Path, localPath.path, "--profile", profile)
    }

    /// Upload with progress callback. Returns when complete.
    public func uploadS3(
        localPath: URL,
        bucket: String,
        key: String,
        metadata: [String: String] = [:],
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let s3Path = "s3://\(bucket)/\(key)"
        var args = ["aws", "s3", "cp", localPath.path, s3Path, "--profile", profile]
        if !metadata.isEmpty {
            let metaString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            args += ["--metadata", metaString]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args

        // Use a pseudo-TTY for stderr so aws cli outputs progress
        // (it suppresses progress when stderr is a pipe)
        var primary: Int32 = 0
        var replica: Int32 = 0
        guard openpty(&primary, &replica, nil, nil, nil) == 0 else {
            throw ProcessError(exitCode: -1, stderr: "Failed to create pseudo-TTY")
        }

        process.standardError = FileHandle(fileDescriptor: replica, closeOnDealloc: false)
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        // Close replica (child side) in parent — process inherited it
        close(replica)

        // Read progress from primary (parent side) of the PTY
        let primaryFD = primary
        let progressTask = Task.detached {
            let handle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: false)
            var buffer = ""
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                guard let chunk = String(data: data, encoding: .utf8) else { continue }
                buffer += chunk
                while let newlineIdx = buffer.firstIndex(of: "\r") ?? buffer.firstIndex(of: "\n") {
                    let line = String(buffer[buffer.startIndex...newlineIdx])
                    buffer = String(buffer[buffer.index(after: newlineIdx)...])
                    // aws s3 cp outputs: "Completed 5.0 MiB/10.0 MiB ..."
                    if let range = line.range(of: #"Completed (\d+\.?\d*) [A-Za-z]+/(\d+\.?\d*)"#, options: .regularExpression) {
                        let matched = line[range]
                        let nums = matched.split(separator: "/")
                        if nums.count == 2 {
                            let parts = nums[0].split(separator: " ")
                            if parts.count >= 2,
                               let completed = Double(parts[1]),
                               let total = Double(nums[1].split(separator: " ").first ?? ""),
                               total > 0 {
                                onProgress(min(completed / total, 1.0))
                            }
                        }
                    }
                }
            }
        }

        // Wait on a real thread to avoid blocking cooperative pool
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                close(primaryFD)
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ProcessError(
                        exitCode: process.terminationStatus,
                        stderr: "Upload failed with exit code \(process.terminationStatus)"
                    ))
                }
            }
        }

        progressTask.cancel()
        onProgress(1.0)
    }

    /// Returns true if an object exists at the given S3 key.
    public func existsS3(bucket: String, key: String) async -> Bool {
        do {
            let _ = try await run("aws", "s3api", "head-object", "--bucket", bucket, "--key", key, "--profile", profile)
            return true
        } catch {
            return false
        }
    }

    public func deleteS3(bucket: String, key: String) async throws {
        let s3Path = "s3://\(bucket)/\(key)"
        let _ = try await run("aws", "s3", "rm", s3Path, "--profile", profile)
    }

    public func copyS3(bucket: String, fromKey: String, toKey: String) async throws {
        let src = "s3://\(bucket)/\(fromKey)"
        let dst = "s3://\(bucket)/\(toKey)"
        let _ = try await run("aws", "s3", "cp", src, dst, "--profile", profile)
    }

    // MARK: - Process Runner

    /// Runs a CLI command on a background dispatch queue (not the cooperative thread pool)
    /// and drains pipes concurrently with the process to avoid pipe-buffer deadlocks.
    private func run(_ args: String...) async throws -> (stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = args

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

                // Read pipes on separate threads to prevent deadlock when
                // process output exceeds the pipe buffer (~64KB).
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

                process.waitUntilExit()
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

public struct ProcessError: Error, LocalizedError, Sendable {
    public let exitCode: Int32
    public let stderr: String
    public var errorDescription: String? { stderr.isEmpty ? "Process exited with code \(exitCode)" : stderr }
}
