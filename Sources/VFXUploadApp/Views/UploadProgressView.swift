import SwiftUI
import VFXUploadCore

struct UploadProgressView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Uploading...")
                    .font(.headline)
                Spacer()
                Text("\(appState.uploadManager.completedCount)/\(appState.uploadManager.totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            overallProgress

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(appState.jobs) { job in
                        FileRowView(job: job)
                    }
                }
            }
        }
        .padding(12)
    }

    private var overallProgress: some View {
        ProgressView(
            value: Double(appState.uploadManager.completedCount),
            total: max(Double(appState.uploadManager.totalCount), 1)
        )
        .progressViewStyle(.linear)
        .accessibilityLabel("Overall upload progress")
        .accessibilityValue("\(appState.uploadManager.completedCount) of \(appState.uploadManager.totalCount) completed")
    }
}
