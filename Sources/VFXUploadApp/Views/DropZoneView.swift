import SwiftUI
import UniformTypeIdentifiers
import VFXUploadCore

struct DropZoneView: View {
    @EnvironmentObject var appState: AppState
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundStyle(isTargeted ? .blue : .secondary)
                .accessibilityHidden(true)

            Text("Drop VFX renders here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Button("Choose Files\u{2026}") { appState.showFilePicker = true }
                .buttonStyle(.bordered)
                .accessibilityLabel("Choose files to upload")
                .accessibilityHint("Opens a file picker to select VFX render files")
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.blue : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
        }
        .padding(12)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .fileImporter(
            isPresented: $appState.showFilePicker,
            allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie, .video],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appState.addFiles(urls: urls)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                let _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        appState.addFiles(urls: [url])
                    }
                }
            }
        }
    }
}
