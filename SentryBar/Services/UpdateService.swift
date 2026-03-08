import Foundation

/// Lightweight update checker that queries GitHub Releases API
/// Battery-friendly: checks at most once per 24 hours, no background polling
final class UpdateService {
    private static let releasesURL = "https://api.github.com/repos/constripacity/SentryBar/releases/latest"
    private static let checkIntervalSeconds: TimeInterval = 86400 // 24 hours

    struct UpdateInfo {
        let latestVersion: String
        let currentVersion: String
        let releaseURL: String

        var isNewer: Bool {
            latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending
        }
    }

    /// Check for updates. Returns nil if already checked recently, no network, or up to date.
    func checkForUpdate() async -> UpdateInfo? {
        // Respect cooldown — don't check more than once per 24h
        let lastCheck = UserDefaults.standard.double(forKey: "com.sentrybar.lastUpdateCheck")
        if lastCheck > 0, Date().timeIntervalSince1970 - lastCheck < Self.checkIntervalSeconds {
            return nil
        }

        guard let url = URL(string: Self.releasesURL) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("SentryBar", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "com.sentrybar.lastUpdateCheck")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else {
                return nil
            }

            // Strip "v" prefix from tag (e.g., "v0.7.0" → "0.7.0")
            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            let info = UpdateInfo(latestVersion: latestVersion, currentVersion: currentVersion, releaseURL: htmlURL)
            return info.isNewer ? info : nil
        } catch {
            return nil
        }
    }
}
