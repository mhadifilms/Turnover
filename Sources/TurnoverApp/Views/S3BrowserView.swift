import SwiftUI
import TurnoverCore

struct S3BrowserView: View {
    let awsService: AWSCLIService
    let bucket: String
    let initialPrefix: String
    let initialFilename: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var currentPrefix: String = ""
    @State private var pathHistory: [String] = []
    @State private var folders: [String] = []
    @State private var files: [String] = []
    @State private var filename: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cache: [String: (folders: [String], files: [String])] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack(spacing: 6) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(pathHistory.isEmpty)

                Text(breadcrumb)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Content area
            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") { loadCurrentPrefix() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
            } else if folders.isEmpty && files.isEmpty {
                Spacer()
                Text("Empty folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(folders, id: \.self) { folder in
                            Button { navigateInto(folder) } label: {
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
                            Divider().padding(.leading, 34)
                        }

                        ForEach(files, id: \.self) { file in
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
                            if file != files.last {
                                Divider().padding(.leading, 34)
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer
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
                        let path = currentPrefix + filename
                        onSelect(path)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(filename.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
        }
        .frame(width: 450, height: 400)
        .onAppear {
            currentPrefix = initialPrefix
            filename = initialFilename
            loadCurrentPrefix()
        }
    }

    // MARK: - Computed

    private var breadcrumb: String {
        if currentPrefix.isEmpty { return "/" }
        return currentPrefix
    }

    // MARK: - Navigation

    private func navigateInto(_ folder: String) {
        pathHistory.append(currentPrefix)
        currentPrefix = currentPrefix + folder
        loadCurrentPrefix()
    }

    private func goBack() {
        guard let previous = pathHistory.popLast() else { return }
        currentPrefix = previous
        loadCurrentPrefix()
    }

    private func loadCurrentPrefix() {
        // Use cache if available
        if let cached = cache[currentPrefix] {
            folders = cached.folders
            files = cached.files
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        folders = []
        files = []
        Task {
            do {
                let result = try await awsService.listS3Contents(bucket: bucket, prefix: currentPrefix)
                folders = result.folders
                files = result.files
                cache[currentPrefix] = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
