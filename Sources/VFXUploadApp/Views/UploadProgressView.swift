import SwiftUI
import VFXUploadCore

struct UploadProgressView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            overallProgress
                .padding(12)

            Divider()

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
        }
    }

    private var overallProgress: some View {
        VStack(spacing: 4) {
            ProgressView(
                value: Double(appState.uploadManager.completedCount),
                total: max(Double(appState.uploadManager.totalCount), 1)
            )
            .progressViewStyle(.linear)
            .accessibilityLabel("Overall progress")
            .accessibilityValue("\(appState.uploadManager.completedCount) of \(appState.uploadManager.totalCount) completed")

            HStack {
                Text(appState.uploadManager.isTagging ? "Tagging\u{2026}" : "Uploading\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.uploadManager.completedCount)/\(appState.uploadManager.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
