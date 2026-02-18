import SwiftUI
import VFXUploadCore

struct FileRowView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var job: UploadJob

    @State private var showDeleteConfirmation = false
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.fileName)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    if !job.s3DestinationPath.isEmpty {
                        Text(abbreviatedPath(job.s3DestinationPath))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    statusText
                }
                Spacer()
                actions
            }

            if job.isEditing {
                editingView
            }

            if isRenaming {
                renameView
            }

            if case .uploading(let progress) = job.status {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Upload progress")
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .alert("Delete from S3?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                appState.deleteFromS3(job: job)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete:\n\(job.s3DestinationPath)")
        }
    }

    private var statusIcon: some View {
        Group {
            switch job.status {
            case .pending:
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Pending")
            case .resolvingPath:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Resolving path")
            case .muxingAudio:
                Image(systemName: "waveform")
                    .foregroundStyle(.purple)
                    .accessibilityLabel("Muxing audio")
            case .taggingColor:
                Image(systemName: "paintpalette")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Tagging color space")
            case .tagged:
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.teal)
                    .accessibilityLabel("Tagged")
            case .uploading:
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Uploading")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Completed")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Failed")
            }
        }
    }

    private var statusText: some View {
        Group {
            switch job.status {
            case .pending:
                if job.parsed == nil {
                    Text("Unrecognized filename — set path manually")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Ready to upload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .resolvingPath:
                Text("Resolving S3 path\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .muxingAudio:
                Text("Muxing audio\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.purple)
            case .taggingColor:
                Text("Tagging color space\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .tagged:
                let modified = job.fileToUpload != job.sourceURL
                Text(modified
                     ? "Tagged (\(job.fileToUpload.lastPathComponent)) — ready to upload"
                     : "Tagged (no changes needed) — ready to upload")
                    .font(.caption)
                    .foregroundStyle(.teal)
            case .uploading(let progress):
                Text("Uploading \(job.fileToUpload.lastPathComponent)\u{2026} \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.blue)
            case .completed:
                Text("Upload complete")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if case .completed = job.status {
                Button { appState.previewFile(for: job) } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
                .help("Preview in QuickTime")
                .accessibilityLabel("Preview \(job.fileName) in QuickTime")

                Button { appState.copyS3URI(for: job) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy S3 URI")
                .accessibilityLabel("Copy S3 URI for \(job.fileName)")

                Button {
                    renameText = job.s3DestinationPath.split(separator: "/").last.map(String.init) ?? job.fileName
                    isRenaming.toggle()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Rename on S3")
                .accessibilityLabel("Rename \(job.fileName) on S3")

                Button { showDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Delete from S3")
                .accessibilityLabel("Delete \(job.fileName) from S3")
                .accessibilityHint("Permanently deletes this file")
            } else if case .failed = job.status {
                Button { appState.removeJob(job) } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove")
                .accessibilityLabel("Remove \(job.fileName)")
            } else {
                Button { job.isEditing.toggle() } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Edit destination path")
                .accessibilityLabel("Edit destination path for \(job.fileName)")

                Button { appState.removeJob(job) } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove")
                .accessibilityLabel("Remove \(job.fileName)")
            }
        }
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("S3 destination key", text: $job.s3DestinationPath)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .accessibilityLabel("S3 destination path")
                .accessibilityHint("Edit the upload destination path")

            HStack {
                Picker("Color Space", selection: $job.colorSpace) {
                    ForEach(ColorSpace.allCases, id: \.self) { cs in
                        Text(cs.displayName).tag(cs)
                    }
                }
                .font(.caption)
                .controlSize(.small)

                Spacer()

                Button("Done") { job.isEditing = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }

    private var renameView: some View {
        HStack(spacing: 6) {
            TextField("New filename", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { commitRename() }
                .accessibilityLabel("New filename")
                .accessibilityHint("Enter a new name for the file on S3")

            Button("Rename") { commitRename() }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Cancel") { isRenaming = false }
                .buttonStyle(.plain)
                .controlSize(.small)
        }
        .padding(.top, 4)
    }

    private func commitRename() {
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        isRenaming = false
        appState.renameOnS3(job: job, newFileName: newName)
    }

    private func abbreviatedPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count > 4 {
            return ".../" + components.suffix(4).joined(separator: "/")
        }
        return path
    }
}
