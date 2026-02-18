import SwiftUI
import VFXUploadCore

struct CredentialView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("AWS SSO Sign-In Required")
                .font(.headline)

            statusText

            if let ssoError = appState.ssoError {
                Label(ssoError, systemImage: "xmark.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(action: { appState.ssoLogin() }) {
                Label("Sign In with SSO", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isCheckingCredentials)
            .accessibilityLabel("Sign in with AWS SSO")
            .accessibilityHint("Opens browser for authentication")

            Button("Check Again") {
                Task { await appState.checkCredentials() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
            .accessibilityLabel("Check credentials again")
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var statusText: some View {
        Group {
            switch appState.credentialStatus {
            case .expired:
                Label("Session expired", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .notConfigured:
                Label("AWS CLI not configured", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            case .error(let msg):
                Label(msg, systemImage: "xmark.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            default:
                EmptyView()
            }
        }
    }
}
