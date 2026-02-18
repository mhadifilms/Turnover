import SwiftUI
import VFXUploadCore

struct ProjectPickerView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedProject: Project?

    var body: some View {
        Picker("Project", selection: $selectedProject) {
            Text("Auto-detect").tag(nil as Project?)
            Divider()
            ForEach(appState.projects) { project in
                Text(project.displayName).tag(project as Project?)
            }
        }
        .pickerStyle(.menu)
    }
}
