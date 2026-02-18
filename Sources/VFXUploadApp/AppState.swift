import SwiftUI
import Combine
import AppKit
import VFXUploadCore

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
    @Published var isDownloadingFFmpeg = false
    @Published var isInstallingAWS = false
    @Published var setupOutput: String = ""
    @Published var ssoStartURL: String = ""
    @Published var ssoRegion: String = "us-east-1"
    @Published var ssoAccountID: String = ""
    @Published var ssoRoleName: String = ""
    @Published var credentialStatus: AWSCredentialStatus = .expired
    @Published var isCheckingCredentials = false
    @Published var jobs: [UploadJob] = []
    @AppStorage("defaultColorSpace") private var colorSpaceRawValue: String = ColorSpace.p3D65PQ.rawValue
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
        dependencyStatus = DependencyCheck.check()
    }

    func downloadFFmpeg() {
        isDownloadingFFmpeg = true
        setupOutput = ""
        Task {
            do {
                try await DependencyCheck.downloadFFmpeg { [weak self] text in
                    Task { @MainActor in self?.setupOutput += text }
                }
                recheckDependencies()
            } catch {
                setupOutput += "\nDownload failed: \(error.localizedDescription)\n"
            }
            isDownloadingFFmpeg = false
        }
    }

    func installAWSCLI() {
        isInstallingAWS = true
        setupOutput = ""
        Task {
            do {
                try await DependencyCheck.installAWSCLI { [weak self] text in
                    Task { @MainActor in self?.setupOutput += text }
                }
            } catch {
                setupOutput += "\nInstall failed: \(error.localizedDescription)\n"
            }
            isInstallingAWS = false
        }
    }

    func saveSSOConfig() {
        do {
            let config = SSOConfig(
                startURL: ssoStartURL,
                region: ssoRegion,
                accountID: ssoAccountID,
                roleName: ssoRoleName
            )
            try DependencyCheck.writeSSOConfig(config)
            recheckDependencies()
        } catch {
            setupOutput = "Failed to save SSO config: \(error.localizedDescription)"
        }
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
        let newJobs = urls.map { url -> UploadJob in
            let job = UploadJob(sourceURL: url)
            // Apply default color space when no project override
            if job.project == nil {
                job.colorSpace = defaultCS
            }
            return job
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
        Task { await uploadManager.tagAll(jobs: jobs) }
    }

    func startUpload() {
        Task { await uploadManager.uploadAll(jobs: jobs) }
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
        let oldKey = job.s3DestinationPath
        // Replace the last path component with the new filename
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
