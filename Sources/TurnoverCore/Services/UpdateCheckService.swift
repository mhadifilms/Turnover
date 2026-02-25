import Foundation

public struct AppRelease: Sendable {
    public let version: String
    public let downloadURL: URL
    public let releaseURL: URL
}

public enum UpdateCheckService {
    private static let repo = "mhadifilms/Turnover"
    private static let apiURL = "https://api.github.com/repos/\(repo)/releases/latest"

    /// Check GitHub for the latest release. Returns nil if already up to date.
    public static func checkForUpdate(currentVersion: String) async -> AppRelease? {
        // Don't check for dev/unknown versions
        let parsed = parseVersion(currentVersion)
        guard parsed != (0, 0, 0) else { return nil }

        guard let url = URL(string: apiURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            guard let tagName = json["tag_name"] as? String else { return nil }
            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            guard isNewer(remote: remoteVersion, than: currentVersion) else { return nil }

            // Find DMG asset
            var downloadURL: URL?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                       let urlStr = asset["browser_download_url"] as? String,
                       let url = URL(string: urlStr) {
                        downloadURL = url
                        break
                    }
                }
            }

            let releaseURL = URL(string: json["html_url"] as? String ?? "https://github.com/\(repo)/releases/latest")!

            return AppRelease(
                version: remoteVersion,
                downloadURL: downloadURL ?? releaseURL,
                releaseURL: releaseURL
            )
        } catch {
            return nil
        }
    }

    /// Semantic version comparison: is `remote` newer than `current`?
    public static func isNewer(remote: String, than current: String) -> Bool {
        let r = parseVersion(remote)
        let c = parseVersion(current)
        return (r.0, r.1, r.2) > (c.0, c.1, c.2)
    }

    private static func parseVersion(_ v: String) -> (Int, Int, Int) {
        let stripped = v.hasPrefix("v") ? String(v.dropFirst()) : v
        let parts = stripped.split(separator: ".").compactMap { Int($0) }
        return (
            parts.count > 0 ? parts[0] : 0,
            parts.count > 1 ? parts[1] : 0,
            parts.count > 2 ? parts[2] : 0
        )
    }
}
