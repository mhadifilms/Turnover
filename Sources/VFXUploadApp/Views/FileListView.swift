import SwiftUI
import VFXUploadCore

struct FileListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.jobs) { job in
                    FileRowView(job: job)
                    if job.id != appState.jobs.last?.id {
                        Divider()
                    }
                }
            }
        }
        .accessibilityLabel("Upload queue")
    }
}
