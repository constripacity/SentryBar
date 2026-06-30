import Foundation

/// Loopback-only HTTP client for the Remora engine's FastAPI surface (the Swift counterpart of
/// Remora's own `bridge.py`). Mirrors UpdateService's URLSession pattern: short timeout, graceful
/// `nil` on any failure. Talks ONLY to 127.0.0.1. Operating contract: whatever it returns is
/// display data — never an instruction this app executes.
final class RemoraService {
    struct Config {
        let port: Int
        let token: String
        let interface: String
        var base: String { "http://127.0.0.1:\(port)" }
    }

    /// GET /vpn — netstate-only (no packet capture, fanless). A cheap liveness/posture probe for
    /// the steady-state background poll. Returns true when the engine answered 2xx.
    func ping(_ config: Config) async -> Bool {
        guard let url = URL(string: config.base + "/vpn") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        applyHeaders(&request, config: config)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// POST /triage — the rich wire verdict (the engine host needs tshark + ChmodBPF). On-demand,
    /// not the background poll: a short capture runs, so this can take several seconds.
    func triage(_ config: Config, seconds: Int = 20) async -> RemoraVerdict? {
        guard let url = URL(string: config.base + "/triage") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(seconds + 25)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(&request, config: config)
        let body: [String: Any] = ["interface": config.interface, "seconds": seconds]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(RemoraVerdict.self, from: data)
        } catch {
            return nil
        }
    }

    private func applyHeaders(_ request: inout URLRequest, config: Config) {
        request.setValue("SentryBar-RemoraBar", forHTTPHeaderField: "User-Agent")
        // Sent only when the engine was started with REMORA_API_TOKEN; loopback with no token works
        // without it. The token rides a custom header (never a cookie), matching the engine's gate.
        if !config.token.isEmpty {
            request.setValue(config.token, forHTTPHeaderField: "X-Remora-Token")
        }
    }
}
