import AppKit
import CryptoKit
import Foundation
import WebKit

/// Moodle's own mobile sign-in handshake (admin/tool/mobile/launch.php), as used by the official app.
/// MBZUAI sets typeoflogin = "in app", so launch.php only issues a token right after a *fresh* login
/// (otherwise "pluginnotenabledorconfigured"); a cookie-less web view guarantees that.
/// Moodle answers by redirecting to moodlemobile://token=BASE64(md5(wwwroot + passport):::token[:::privatetoken]),
/// which the web view intercepts. (ASWebAuthenticationSession showed only a blank window here, hence our own window.)
@MainActor final class MoodleSSO: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var pending: CheckedContinuation<URL, any Error>?

    /// Opens the university sign-in window and returns the web-service token (never logged).
    func signIn(site: URL) async throws -> String {
        let passport = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        var c = URLComponents(url: site.appending(path: "admin/tool/mobile/launch.php"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "service", value: "moodle_mobile_app"), .init(name: "passport", value: passport),
                        .init(name: "urlscheme", value: "moodlemobile")]
        let launch = c.url!
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            pending = cont
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent() // fresh login every time; nothing kept after the window closes
            let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 720), configuration: config)
            web.navigationDelegate = self
            let w = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Sign in — \(site.host() ?? "Moodle")"
            w.contentView = web
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            window = w
            web.load(URLRequest(url: launch))
        }
        return try Self.token(from: callback.absoluteString, site: site, passport: passport)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = action.request.url, url.scheme == "moodlemobile" {
            finish(.success(url))
            return .cancel
        }
        return ["https", "about"].contains(action.request.url?.scheme?.lowercased() ?? "") ? .allow : .cancel
    }

    func windowWillClose(_ notification: Notification) { finish(.failure(MoodleSSOError.cancelled)) }

    private func finish(_ result: Result<URL, any Error>) {
        guard let cont = pending else { return }
        pending = nil
        window?.delegate = nil
        window?.close()
        window = nil
        cont.resume(with: result)
    }

    /// Decodes the callback and checks its signature against the passport we sent, so a forged link is rejected.
    nonisolated static func token(from callback: String, site: URL, passport: String) throws -> String {
        let prefix = "moodlemobile://token="
        guard callback.hasPrefix(prefix) else { throw MoodleSSOError.badReply }
        let b64 = String(callback.dropFirst(prefix.count)).removingPercentEncoding ?? ""
        guard let data = Data(base64Encoded: b64), let text = String(data: data, encoding: .utf8) else { throw MoodleSSOError.badReply }
        let parts = text.components(separatedBy: ":::")
        guard parts.count >= 2, !parts[1].isEmpty else { throw MoodleSSOError.badReply }
        let wwwroot = site.absoluteString // siteURL() already strips trailing slashes
        let expected = Insecure.MD5.hash(data: Data((wwwroot + passport).utf8)).map { String(format: "%02x", $0) }.joined()
        guard parts[0] == expected else { throw MoodleSSOError.signatureMismatch }
        return parts[1]
    }
}

enum MoodleSSOError: LocalizedError {
    case cancelled, badReply, signatureMismatch
    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in cancelled"
        case .badReply: "Moodle sent an unexpected sign-in reply"
        case .signatureMismatch: "Sign-in reply didn't match this request — try again"
        }
    }
}
