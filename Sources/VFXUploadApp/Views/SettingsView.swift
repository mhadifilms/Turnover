import SwiftUI
import UniformTypeIdentifiers
import VFXUploadCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showProjectImporter = false
    @State private var importError: String?

    var body: some View {
        Form {
            Section("Projects") {
                if appState.projects.isEmpty {
                    Text("No project config loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.projects) { project in
                        HStack {
                            Text(project.displayName)
                            Spacer()
                            Text("Ep \(project.episodeNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Button("Import Config\u{2026}") {
                        showProjectImporter = true
                    }

                    if !appState.projects.isEmpty {
                        Button("Remove All", role: .destructive) {
                            appState.removeAllProjects()
                        }
                    }
                }

                if let error = importError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Default Color Space") {
                Picker("Color Space", selection: Binding(
                    get: { appState.selectedColorSpace },
                    set: { appState.selectedColorSpace = $0 }
                )) {
                    ForEach(ColorSpace.allCases, id: \.self) { cs in
                        Text(cs.displayName).tag(cs)
                    }
                }
                Text("Applied to newly added files without a project-specific color space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 350)
        .fileImporter(isPresented: $showProjectImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    try appState.importProjects(from: url)
                    importError = nil
                } catch {
                    importError = "Import failed: \(error.localizedDescription)"
                }
            case .failure(let error):
                importError = "File picker error: \(error.localizedDescription)"
            }
        }
    }
}
