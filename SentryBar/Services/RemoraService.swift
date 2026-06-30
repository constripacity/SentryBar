import Foundation

/// Loopback-only HTTP client for the Remora engine's FastAPI surface (the Swift counterpart of
/// Remora's own `bridge.py`). Short timeouts, graceful `nil` on any failure, and a hard cap on the
/// accepted response so a hostile/buggy loopback peer can't balloon memory. Talks ONLY to
/// 127.0.0.1. Operating contract: whatever it returns is display data — never executed.
final class RemoraService: Sendable {
    struct Config {
        let port: Int
        let token: String
        let interface: String
        var base: String { "http://127.0.0.1:\(port)" }
    }

    /// A dedicated ephemeral session: no cache / cookies / credential store for a loopback API,
    /// and a hard `timeoutIntervalForResource` ceiling so a slow-drip peer can't keep a transfer
    /// alive indefinitely (the URLSession default is 7 days). Defense-in-depth — the engine is
    /// normally our own local process, but the app trusts nothing on the wire by design.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 45        // idle timeout between bytes
        cfg.timeoutIntervalForResource = 90        // hard ceiling on the whole transfer
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        return URLSession(configuration: cfg)
    }()

    /// A real verdict is a few KB; reject anything wildly larger before decoding.
    private static let maxResponseBytes: Int64 = 8 * 1024 * 1024   // 8 MB

    /// GET /vpn — netstate-only (no packet capture, fanless). A cheap liveness/posture probe for
    /// the steady-state background poll. Returns true when the engine answered 2xx.
    func ping(_ config: Config) async -> Bool {
        guard let url = URL(string: config.base + "/vpn") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        applyHeaders(&request, config: config)
        do {
            let (_, response) = try await session.data(for: request)
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
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            // Reject an oversized body — declared (Content-Length) or actual — before decoding.
            if http.expectedContentLength > Self.maxResponseBytes { return nil }
            guard Int64(data.count) <= Self.maxResponseBytes else { return nil }
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
