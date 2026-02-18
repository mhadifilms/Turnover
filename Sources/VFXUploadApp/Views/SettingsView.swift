import SwiftUI
import VFXUploadCore

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Picker("Default Color Space", selection: Binding(
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
        .formStyle(.grouped)
        .frame(width: 350)
    }
}
