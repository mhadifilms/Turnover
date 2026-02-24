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

    /// Detect CPU architecture at runtime for correct binary downloads.
    private static var cpuArchitecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

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

        let arch = cpuArchitecture
        let downloadArch = arch == "x86_64" ? "amd64" : "arm64"

        for tool in ["ffmpeg", "ffprobe"] {
            onOutput("Downloading \(tool) (\(arch))...\n")

            let zipURL = "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(downloadArch)/snapshot/\(tool).zip"
            let zipPath = fm.temporaryDirectory.appendingPathComponent("\(tool)-\(UUID().uuidString).zip").path

            defer { try? fm.removeItem(atPath: zipPath) }

            // curl download with -f to fail on HTTP errors
            let curlProcess = Process()
            curlProcess.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            curlProcess.arguments = ["-fL", "--tlsv1.2", "-o", zipPath, zipURL]

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

            // Verify the downloaded file is a valid zip (check magic bytes)
            guard let zipData = fm.contents(atPath: zipPath),
                  zipData.count > 4,
                  zipData[0] == 0x50, zipData[1] == 0x4B else {
                throw DependencyError.installFailed("Downloaded \(tool) file is not a valid zip archive")
            }

            // unzip — only extract the tool binary, not arbitrary paths
            onOutput("Extracting \(tool)...\n")
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipPath, tool, "-d", binDir]
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

            let toolPath = "\(binDir)/\(tool)"

            // Remove quarantine attribute so Gatekeeper doesn't block execution
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-d", "com.apple.quarantine", toolPath]
            xattrProcess.standardOutput = FileHandle.nullDevice
            xattrProcess.standardError = FileHandle.nullDevice
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            // chmod +x and verify
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", toolPath]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()
            guard chmodProcess.terminationStatus == 0 else {
                throw DependencyError.installFailed("Failed to make \(tool) executable")
            }

            // Verify the binary is actually executable
            guard fm.isExecutableFile(atPath: toolPath) else {
                throw DependencyError.installFailed("\(tool) is not executable after chmod")
            }

            onOutput("\(tool) installed to \(toolPath)\n")
        }

        onOutput("Done!\n")
    }

    // MARK: - AWS CLI Install

    /// Download the AWS CLI v2 macOS pkg and open it for the user to install.
    public static func installAWSCLI(onOutput: @Sendable @escaping (String) -> Void) async throws {
        let fm = FileManager.default
        let pkgURL = "https://awscli.amazonaws.com/AWSCLIV2.pkg"
        let pkgPath = fm.temporaryDirectory.appendingPathComponent("AWSCLIV2-\(UUID().uuidString).pkg").path

        defer { try? fm.removeItem(atPath: pkgPath) }

        onOutput("Downloading AWS CLI installer...\n")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-fL", "--tlsv1.2", "-o", pkgPath, pkgURL]

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

        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = [pkgPath]
        try openProcess.run()
        openProcess.waitUntilExit()
        guard openProcess.terminationStatus == 0 else {
            throw DependencyError.installFailed("Failed to open AWS CLI installer")
        }

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
