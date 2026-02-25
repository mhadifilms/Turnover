import SwiftUI
import Combine
import AppKit
import TurnoverCore

@MainActor
public final class AppState: ObservableObject {
    // Services
    let awsService: AWSCLIService
    let resolver: S3PathResolver
    let audioMuxer: AudioMuxingService
    let uploadManager: UploadManager
    let historyStore = JobHistoryStore()

    // State
    @Published var dependencyStatus: DependencyStatus = DependencyCheck.check()
    @Published var projects: [Project] = ProjectStore.load()
    @Published var configText: String = ProjectStore.loadText()
    @Published var configError: String?
    @Published var isDownloadingFFmpeg = false
    @Published var isInstallingAWS = false
    @Published var setupOutput: String = ""
    @Published var setupError: String?
    @Published var credentialStatus: AWSCredentialStatus = .expired
    @Published var isCheckingCredentials = true
    @Published var jobs: [UploadJob] = []
    @AppStorage("defaultColorSpace") private var colorSpaceRawValue: String = ColorSpace.p3D65PQ.rawValue
    @AppStorage("enableAudioMuxing") var enableAudioMuxing: Bool = true
    @Published var showFilePicker = false
    @Published var ssoError: String?

    var selectedColorSpace: ColorSpace {
        get { ColorSpace(rawValue: colorSpaceRawValue) ?? .p3D65PQ }
        set {
            colorSpaceRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        let aws = AWSCLIService()
        let resolver = S3PathResolver(aws: aws)
        let muxer = AudioMuxingService(aws: aws, resolver: resolver)
        self.awsService = aws
        self.resolver = resolver
        self.audioMuxer = muxer
        self.uploadManager = UploadManager(aws: aws, resolver: resolver, audioMuxer: muxer)

        // Forward UploadManager's changes so views re-render
        uploadManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        loadJobs()
        Task { await checkCredentials() }
    }

    var isAuthenticated: Bool {
        if case .valid = credentialStatus { return true }
        return false
    }

    var hasJobs: Bool { !jobs.isEmpty }

    var canTag: Bool {
        isAuthenticated
        && !uploadManager.isTagging
        && !uploadManager.isUploading
        && jobs.contains(where: {
            if case .pending = $0.status, !$0.s3DestinationPath.isEmpty { return true }
            return false
        })
    }

    var canUpload: Bool {
        isAuthenticated
        && !uploadManager.isUploading
        && !uploadManager.isTagging
        && jobs.contains(where: { if case .tagged = $0.status { return true }; return false })
        && !jobs.contains(where: {
            if case .pending = $0.status, !$0.s3DestinationPath.isEmpty { return true }
            return false
        })
    }

    func checkCredentials() async {
        isCheckingCredentials = true
        credentialStatus = await awsService.checkCredentials()
        isCheckingCredentials = false
    }

    func recheckDependencies() {
        DependencyCheck.simulateCleanInstall = false
        dependencyStatus = DependencyCheck.check()
        if dependencyStatus.isReady {
            Task { await checkCredentials() }
        }
    }

    func reloadProjects() {
        projects = ProjectStore.load()
        configText = ProjectStore.loadText()
        configError = nil
    }

    func saveConfigText() {
        do {
            try ProjectStore.saveText(configText)
            projects = ProjectStore.load()
            configText = ProjectStore.loadText()
            configError = nil
            recheckDependencies()
        } catch {
            configError = error.localizedDescription
        }
    }

    func removeAllProjects() {
        ProjectStore.removeConfig()
        reloadProjects()
        recheckDependencies()
    }

    func downloadFFmpeg() {
        isDownloadingFFmpeg = true
        setupOutput = ""
        setupError = nil
        Task {
            do {
                try await DependencyCheck.downloadFFmpeg { [weak self] text in
                    Task { @MainActor in self?.setupOutput += text }
                }
            } catch {
                setupError = "Download failed: \(error.localizedDescription)"
            }
            isDownloadingFFmpeg = false
            recheckDependencies()
        }
    }

    func installAWSCLI() {
        isInstallingAWS = true
        setupOutput = ""
        setupError = nil
        Task {
            do {
                try await DependencyCheck.installAWSCLI { [weak self] text in
                    Task { @MainActor in self?.setupOutput += text }
                }
            } catch {
                setupError = "Install failed: \(error.localizedDescription)"
            }
            isInstallingAWS = false
            recheckDependencies()
        }
    }

    func openSSOConfigInTerminal() {
        let awsPath = DependencyCheck.findExecutable("aws") ?? "aws"
        let scriptContent = "#!/bin/bash\n\"\(awsPath)\" configure sso\n"
        let tmp = "/tmp/turnover-sso-config.command"
        try? scriptContent.write(toFile: tmp, atomically: true, encoding: .utf8)
        chmod(tmp, 0o755)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", tmp]
        try? process.run()
    }

    func ssoLogin() {
        ssoError = nil
        Task {
            do {
                try await awsService.ssoLogin()
                await checkCredentials()
            } catch {
                ssoError = error.localizedDescription
            }
        }
    }

    func addFiles(urls: [URL]) {
        let defaultCS = selectedColorSpace
        var allURLs: [URL] = []

        // Expand folders into their contents
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    allURLs.append(contentsOf: contents)
                }
            } else {
                allURLs.append(url)
            }
        }

        // Parse all files — only accept files matching the naming convention
        var sequenceFrames: [String: (parsed: ParsedFileName, urls: [URL])] = [:]
        var singleFiles: [URL] = []

        for url in allURLs {
            guard let parsed = FileNameParser.parse(fileName: url.lastPathComponent) else { continue }
            if parsed.isSequenceFrame {
                // Group frames by sequence base name + extension
                let key = "\(parsed.sequenceBaseName).\(parsed.fileExtension)"
                if sequenceFrames[key] == nil {
                    sequenceFrames[key] = (parsed: parsed, urls: [])
                }
                sequenceFrames[key]!.urls.append(url)
            } else {
                singleFiles.append(url)
            }
        }

        var newJobs: [UploadJob] = []

        // Create sequence jobs
        for (key, seq) in sequenceFrames {
            let sorted = seq.urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
            let frames = sorted.compactMap { FileNameParser.parse(fileName: $0.lastPathComponent)?.frameNumber }
            let range = frames.isEmpty ? "?" : "\(frames.first!)-\(frames.last!)"
            let baseName = seq.parsed.sequenceBaseName

            let job = UploadJob(sequenceURLs: sorted, baseName: baseName, frameRange: range, parsed: seq.parsed)
            if job.project == nil { job.colorSpace = defaultCS }
            newJobs.append(job)
        }

        // Create single-file jobs
        for url in singleFiles {
            let job = UploadJob(sourceURL: url)
            if job.project == nil { job.colorSpace = defaultCS }
            newJobs.append(job)
        }

        jobs.append(contentsOf: newJobs)

        for job in newJobs {
            observeJob(job)
        }
        saveJobs()

        // Resolve paths for each new job in background
        for job in newJobs {
            Task { await uploadManager.resolvePath(for: job) }
        }
    }

    func removeJob(_ job: UploadJob) {
        jobs.removeAll { $0.id == job.id }
        saveJobs()
    }

    func clearCompleted() {
        jobs.removeAll { $0.status == .completed }
        saveJobs()
    }

    func startTagging() {
        uploadManager.activeTask = Task { await uploadManager.tagAll(jobs: jobs, enableAudioMuxing: enableAudioMuxing) }
    }

    func startUpload() {
        uploadManager.activeTask = Task { await uploadManager.uploadAll(jobs: jobs) }
    }

    func cancelOperation() {
        uploadManager.cancel()
        // Reset in-progress jobs back to their pre-operation status
        for job in jobs {
            switch job.status {
            case .muxingAudio, .taggingColor:
                job.status = .pending
            case .uploading:
                job.status = .tagged
            default:
                break
            }
        }
    }

    // MARK: - Post-Upload Actions

    func copyS3URI(for job: UploadJob) {
        guard let uri = job.s3URI else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(uri, forType: .string)
    }

    func deleteFromS3(job: UploadJob) {
        guard let project = job.project, !job.s3DestinationPath.isEmpty else { return }
        Task {
            do {
                try await awsService.deleteS3(bucket: project.s3Bucket, key: job.s3DestinationPath)
                removeJob(job)
            } catch {
                job.status = .failed("Delete failed: \(error.localizedDescription)")
            }
        }
    }

    func renameOnS3(job: UploadJob, newFileName: String) {
        guard let project = job.project, !job.s3DestinationPath.isEmpty else { return }
        // Validate filename: no path separators or traversal
        guard !newFileName.isEmpty,
              !newFileName.contains("/"),
              !newFileName.contains("\\"),
              !newFileName.contains(".."),
              !newFileName.hasPrefix(".") else {
            job.status = .failed("Invalid filename")
            return
        }
        let oldKey = job.s3DestinationPath
        let components = oldKey.split(separator: "/", omittingEmptySubsequences: false)
        let newKey = components.dropLast().joined(separator: "/") + "/" + newFileName
        guard newKey != oldKey else { return }
        Task {
            do {
                try await awsService.copyS3(bucket: project.s3Bucket, fromKey: oldKey, toKey: newKey)
                try await awsService.deleteS3(bucket: project.s3Bucket, key: oldKey)
                job.s3DestinationPath = newKey
                self.saveJobs()
            } catch {
                job.status = .failed("Rename failed: \(error.localizedDescription)")
            }
        }
    }

    func previewFile(for job: UploadJob) {
        let quickTimePath = "/System/Applications/QuickTime Player.app"
        let quickTimeURL = URL(fileURLWithPath: quickTimePath)
        NSWorkspace.shared.open(
            [job.fileToUpload],
            withApplicationAt: quickTimeURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    // MARK: - Persistence

    private func observeJob(_ job: UploadJob) {
        job.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                // Save after @Published willSet fires — async to read new value
                DispatchQueue.main.async { [weak self] in
                    if job.status.isTerminal || job.status == .tagged {
                        self?.saveJobs()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func saveJobs() {
        let persisted = jobs.map { PersistedJob(from: $0) }
        historyStore.save(persisted)
    }

    private func loadJobs() {
        let persisted = historyStore.load()
        guard !persisted.isEmpty else { return }
        let restored = persisted.map { $0.toUploadJob() }
        jobs = restored
        for job in restored {
            observeJob(job)
        }
    }

}
