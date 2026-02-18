import Foundation

public struct DependencyStatus: Sendable {
    public let ffmpegPath: String?
    public let ffprobePath: String?
    public let awsPath: String?
    public let hasSSOConfig: Bool
    public let hasProjects: Bool

    public var hasFFmpeg: Bool { ffmpegPath != nil }
    public var hasFFprobe: Bool { ffprobePath != nil }
    public var hasAWS: Bool { awsPath != nil }
    public var isReady: Bool { hasFFmpeg && hasFFprobe && hasAWS && hasSSOConfig && hasProjects }
}


public enum DependencyCheck {
    /// App-specific bin directory for downloaded tools
    public static let appSupportBinDir: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VFXUpload/bin").path
    }()

    private static let searchPaths = [
        appSupportBinDir,
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
    ]

    /// Set to `true` to simulate a clean install with nothing configured.
    public static var simulateCleanInstall = false

    public static func check() -> DependencyStatus {
        if simulateCleanInstall {
            return DependencyStatus(
                ffmpegPath: nil,
                ffprobePath: nil,
                awsPath: nil,
                hasSSOConfig: false,
                hasProjects: false
            )
        }
        return DependencyStatus(
            ffmpegPath: findExecutable("ffmpeg"),
            ffprobePath: findExecutable("ffprobe"),
            awsPath: findExecutable("aws"),
            hasSSOConfig: checkSSOConfig(),
            hasProjects: !ProjectStore.load().isEmpty
        )
    }

    // MARK: - ffmpeg Download

    /// Download static ffmpeg + ffprobe binaries to app support bin dir.
    public static func downloadFFmpeg(onOutput: @Sendable @escaping (String) -> Void) async throws {
        let binDir = appSupportBinDir
        let fm = FileManager.default
        if !fm.fileExists(atPath: binDir) {
            try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        }

        for tool in ["ffmpeg", "ffprobe"] {
            onOutput("Downloading \(tool)...\n")

            let zipURL = "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/snapshot/\(tool).zip"
            let zipPath = NSTemporaryDirectory() + "\(tool).zip"

            // curl download
            let curlProcess = Process()
            curlProcess.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            curlProcess.arguments = ["-L", "-o", zipPath, zipURL]

            let curlPipe = Pipe()
            curlProcess.standardError = curlPipe
            curlProcess.standardOutput = FileHandle.nullDevice

            try curlProcess.run()

            let curlHandle = curlPipe.fileHandleForReading
            Task.detached {
                while true {
                    let data = curlHandle.availableData
                    if data.isEmpty { break }
                    if let text = String(data: data, encoding: .utf8) {
                        onOutput(text)
                    }
                }
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global().async {
                    curlProcess.waitUntilExit()
                    if curlProcess.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: DependencyError.installFailed(
                            "Failed to download \(tool) (exit code \(curlProcess.terminationStatus))"
                        ))
                    }
                }
            }

            // unzip
            onOutput("Extracting \(tool)...\n")
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipPath, "-d", binDir]
            unzipProcess.standardOutput = FileHandle.nullDevice
            unzipProcess.standardError = FileHandle.nullDevice

            try unzipProcess.run()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global().async {
                    unzipProcess.waitUntilExit()
                    if unzipProcess.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: DependencyError.installFailed(
                            "Failed to extract \(tool)"
                        ))
                    }
                }
            }

            // chmod +x
            let toolPath = "\(binDir)/\(tool)"
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", toolPath]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()

            // cleanup zip
            try? fm.removeItem(atPath: zipPath)

            onOutput("\(tool) installed to \(toolPath)\n")
        }

        onOutput("Done!\n")
    }

    // MARK: - AWS CLI Install

    /// Download the AWS CLI v2 macOS pkg and open it for the user to install.
    public static func installAWSCLI(onOutput: @Sendable @escaping (String) -> Void) async throws {
        let pkgURL = "https://awscli.amazonaws.com/AWSCLIV2.pkg"
        let pkgPath = NSTemporaryDirectory() + "AWSCLIV2.pkg"

        onOutput("Downloading AWS CLI installer...\n")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-L", "-o", pkgPath, pkgURL]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()

        let handle = pipe.fileHandleForReading
        Task.detached {
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    onOutput(text)
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DependencyError.installFailed(
                        "Failed to download AWS CLI installer"
                    ))
                }
            }
        }

        onOutput("Opening installer...\n")

        // Open the pkg installer for the user
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = [pkgPath]
        try openProcess.run()
        openProcess.waitUntilExit()

        onOutput("AWS CLI installer opened. Follow the prompts to install, then click \"Check Again\".\n")
    }

    // MARK: - SSO Config

    /// Check if ~/.aws/config contains an SSO configuration.
    public static func checkSSOConfig() -> Bool {
        let configPath = NSHomeDirectory() + "/.aws/config"
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return false
        }
        return contents.contains("sso_start_url")
    }

    // MARK: - Executable Lookup

    /// Find an executable by name across known search paths.
    public static func findExecutable(_ name: String) -> String? {
        for dir in searchPaths {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}

public enum DependencyError: Error, LocalizedError {
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .installFailed(let msg):
            return msg
        }
    }
}
