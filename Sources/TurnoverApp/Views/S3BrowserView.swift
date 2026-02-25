import SwiftUI
import TurnoverCore

@MainActor
private final class S3BrowserModel: ObservableObject {
    let awsService: AWSCLIService
    let bucket: String

    @Published var currentPrefix: String
    @Published var pathHistory: [String] = []
    @Published var folders: [String] = []
    @Published var files: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cache: [String: (folders: [String], files: [String])] = [:]

    init(awsService: AWSCLIService, bucket: String, initialPrefix: String) {
        self.awsService = awsService
        self.bucket = bucket
        self.currentPrefix = initialPrefix
    }

    var breadcrumb: String {
        if currentPrefix.isEmpty { return "/" }
        let parts = currentPrefix.split(separator: "/")
        if parts.count > 3 {
            return ".../" + parts.suffix(3).joined(separator: "/") + "/"
        }
        return currentPrefix
    }

    var canGoBack: Bool { !pathHistory.isEmpty }

    func load() {
        if let cached = cache[currentPrefix] {
            folders = cached.folders
            files = cached.files
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        folders = []
        files = []

        Task {
            do {
                let result = try await awsService.listS3Contents(bucket: bucket, prefix: currentPrefix)
                self.folders = result.folders
                self.files = result.files
                self.cache[currentPrefix] = result
                self.errorMessage = nil
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func navigateInto(_ folder: String) {
        pathHistory.append(currentPrefix)
        currentPrefix += folder
        load()
    }

    func goBack() {
        guard let previous = pathHistory.popLast() else { return }
        currentPrefix = previous
        load()
    }

    func refresh() {
        cache.removeValue(forKey: currentPrefix)
        load()
    }
}

struct S3BrowserView: View {
    let awsService: AWSCLIService
    let bucket: String
    let initialPrefix: String
    let initialFilename: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @StateObject private var model: S3BrowserModel
    @State private var filename: String

    init(
        awsService: AWSCLIService,
        bucket: String,
        initialPrefix: String,
        initialFilename: String,
        onSelect: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.awsService = awsService
        self.bucket = bucket
        self.initialPrefix = initialPrefix
        self.initialFilename = initialFilename
        self.onSelect = onSelect
        self.onCancel = onCancel
        self._model = StateObject(wrappedValue: S3BrowserModel(
            awsService: awsService,
            bucket: bucket,
            initialPrefix: initialPrefix
        ))
        self._filename = State(initialValue: initialFilename)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 450, height: 400)
        .onAppear { model.load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button { model.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoBack)

            Text(model.breadcrumb)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        } else if let error = model.errorMessage {
            Spacer()
            VStack(spacing: 8) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Retry") { model.load() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        } else if model.folders.isEmpty && model.files.isEmpty {
            Spacer()
            Text("Empty folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.folders, id: \.self) { folder in
                            folderRow(folder)
                        }
                        ForEach(model.files, id: \.self) { file in
                            fileRow(file)
                        }
                    }
                }
            }
        }
    }

    private func folderRow(_ folder: String) -> some View {
        Button { model.navigateInto(folder) } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 16)
                Text(folder.hasSuffix("/") ? String(folder.dropLast()) : folder)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ file: String) -> some View {
        Button { filename = file } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(file)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if filename == file {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Filename:")
                    .font(.caption)
                TextField("filename", text: $filename)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button("Select") {
                    let path = model.currentPrefix + filename
                    onSelect(path)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(filename.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }
}
