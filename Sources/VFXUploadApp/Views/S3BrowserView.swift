import SwiftUI
import VFXUploadCore

struct S3BrowserView: View {
    let awsService: AWSCLIService
    let bucket: String
    let initialPrefix: String
    let initialFilename: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var currentPrefix: String = ""
    @State private var pathHistory: [String] = []
    @State private var items: [String] = []
    @State private var filename: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button {
                    goBack()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                .disabled(pathHistory.isEmpty)

                Spacer()

                Text(breadcrumb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Content area
            if isLoading {
                Spacer()
                ProgressView("Loading\u{2026}")
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
            } else if items.isEmpty {
                Spacer()
                Text("Empty folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(folders, id: \.self) { folder in
                        Button {
                            navigateInto(folder)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(folder)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(files, id: \.self) { file in
                        Button {
                            filename = file
                        } label: {
                            HStack {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                Text(file)
                                    .lineLimit(1)
                                Spacer()
                                if filename == file {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
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
        let components = currentPrefix.split(separator: "/")
        if components.count > 3 {
            return ".../\(components.suffix(3).joined(separator: "/"))/"
        }
        return currentPrefix
    }

    private var folders: [String] {
        items.filter { $0.hasSuffix("/") }
    }

    private var files: [String] {
        items.filter { !$0.hasSuffix("/") }
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
        isLoading = true
        errorMessage = nil
        items = []
        Task {
            do {
                let result = try await awsService.listS3(bucket: bucket, prefix: currentPrefix)
                items = result
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
