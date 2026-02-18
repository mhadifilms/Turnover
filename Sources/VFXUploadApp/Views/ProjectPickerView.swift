import SwiftUI
import VFXUploadCore

struct ProjectPickerView: View {
    @Binding var selectedProject: Project?

    var body: some View {
        Picker("Project", selection: $selectedProject) {
            Text("Auto-detect").tag(nil as Project?)
            Divider()
            ForEach(ProjectCatalog.all) { project in
                Text(project.displayName).tag(project as Project?)
            }
        }
        .pickerStyle(.menu)
    }
}
