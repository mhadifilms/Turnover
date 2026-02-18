import Foundation

public struct DependencyStatus: Sendable {
    public let ffmpegPath: String?
    public let ffprobePath: String?
    public let awsPath: String?
    public let hasSSOConfig: Bool

    public var hasFFmpeg: Bool { ffmpegPath != nil }
    public var hasFFprobe: Bool { ffprobePath != nil }
    public var hasAWS: Bool { awsPath != nil }
    public var isReady: Bool { hasFFmpeg && hasFFprobe && hasAWS && hasSSOConfig }
}

public struct SSOConfig: Sendable {
    public var startURL: String
    public var region: String
    public var accountID: String
    public var roleName: String

    public init(startURL: String, region: String, accountID: String, roleName: String) {
        self.startURL = startURL
        self.region = region
        self.accountID = accountID
        self.roleName = roleName
    }
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

    public static func check() -> DependencyStatus {
        DependencyStatus(
            ffmpegPath: findExecutable("ffmpeg"),
            ffprobePath: findExecutable("ffprobe"),
            awsPath: findExecutable("aws"),
            hasSSOConfig: checkSSOConfig()
        )
    }

    // MARK: - ffmpeg Download

    /// Download static ffmpeg + ffprobe binaries from evermeet.cx to app support bin dir.
    public static func downloadFFmpeg(onOutput: @Sendable @escaping (String) -> Void) async throws {
        let binDir = appSupportBinDir
        let fm = FileManager.default
        if !fm.fileExists(atPath: binDir) {
            try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        }

        for tool in ["ffmpeg", "ffprobe"] {
            onOutput("Downloading \(tool)...\n")

            let zipURL = "https://evermeet.cx/ffmpeg/getrelease/\(tool)/zip"
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

    /// Write an SSO-based AWS config to ~/.aws/config. Backs up any existing file first.
    public static func writeSSOConfig(_ config: SSOConfig) throws {
        let awsDir = NSHomeDirectory() + "/.aws"
        let configPath = awsDir + "/config"
        let fm = FileManager.default

        // Create ~/.aws if needed
        if !fm.fileExists(atPath: awsDir) {
            try fm.createDirectory(atPath: awsDir, withIntermediateDirectories: true)
        }

        // Back up existing config
        if fm.fileExists(atPath: configPath) {
            let backupPath = configPath + ".backup-\(Int(Date().timeIntervalSince1970))"
            try fm.copyItem(atPath: configPath, toPath: backupPath)
        }

        let configContents = """
        [default]
        sso_start_url = \(config.startURL)
        sso_region = \(config.region)
        sso_account_id = \(config.accountID)
        sso_role_name = \(config.roleName)
        region = \(config.region)
        output = json
        """

        try configContents.write(toFile: configPath, atomically: true, encoding: .utf8)
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
