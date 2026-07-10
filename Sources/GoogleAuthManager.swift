import Foundation
import AuthenticationServices
import CryptoKit
import AppKit

final class GoogleAuthManager: NSObject, ObservableObject {
    static let shared = GoogleAuthManager()

    private let clientId      = "34429310373-fb6vc3rr5i7c9c8oi0i7vvueslk18j7m.apps.googleusercontent.com"
    private let redirectScheme = "com.googleusercontent.apps.34429310373-fb6vc3rr5i7c9c8oi0i7vvueslk18j7m"
    private let scope = "openid email https://www.googleapis.com/auth/calendar.readonly"

    @Published var connectedEmails: [String] = []

    var isSignedIn: Bool  { !connectedEmails.isEmpty }
    var userEmail: String? { connectedEmails.first }

    private var accessTokens:  [String: String] = [:]
    private var refreshTokens: [String: String] = [:]
    private var tokenExpiries: [String: Date]   = [:]

    private let kEmails = "missting.connectedEmails"

    override init() {
        super.init()
        migrateIfNeeded()
        loadAll()
    }

    // MARK: - Public

    /// Signs in a new Google account and adds it to the connected accounts list.
    @discardableResult
    func signIn() async throws -> String {
        let (verifier, challenge) = pkce()

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id",             value: clientId),
            .init(name: "redirect_uri",          value: "\(redirectScheme):/oauth2callback"),
            .init(name: "response_type",         value: "code"),
            .init(name: "scope",                 value: scope),
            .init(name: "code_challenge",        value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type",           value: "offline"),
            .init(name: "prompt",                value: "consent"),
        ]

        let code: String = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: comps.url!,
                callbackURLScheme: redirectScheme
            ) { callbackURL, error in
                if let error { cont.resume(throwing: error); return }
                guard
                    let url   = callbackURL,
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                    let code  = items.first(where: { $0.name == "code" })?.value
                else { cont.resume(throwing: AuthError.noCode); return }
                cont.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }

        let tok = try await postToken([
            "client_id":     clientId,
            "code":          code,
            "code_verifier": verifier,
            "grant_type":    "authorization_code",
            "redirect_uri":  "\(redirectScheme):/oauth2callback",
        ])

        let email = try await fetchUserEmail(token: tok.access_token)
        let expiry = Date().addingTimeInterval(TimeInterval(tok.expires_in ?? 3600))

        await MainActor.run {
            accessTokens[email]  = tok.access_token
            if let rt = tok.refresh_token { refreshTokens[email] = rt }
            tokenExpiries[email] = expiry
            if !connectedEmails.contains(email) { connectedEmails.append(email) }
            save(for: email)
        }
        return email
    }

    func getValidToken(for email: String) async throws -> String {
        if let t = accessTokens[email],
           let exp = tokenExpiries[email],
           exp > Date().addingTimeInterval(60) { return t }

        guard let rt = refreshTokens[email] else { throw AuthError.notSignedIn }
        let tok    = try await postToken(["client_id": clientId, "refresh_token": rt, "grant_type": "refresh_token"])
        let expiry = Date().addingTimeInterval(TimeInterval(tok.expires_in ?? 3600))
        await MainActor.run {
            accessTokens[email]  = tok.access_token
            tokenExpiries[email] = expiry
            save(for: email)
        }
        return tok.access_token
    }

    func getValidToken() async throws -> String {
        guard let email = connectedEmails.first else { throw AuthError.notSignedIn }
        return try await getValidToken(for: email)
    }

    func signOut(email: String) {
        accessTokens.removeValue(forKey: email)
        refreshTokens.removeValue(forKey: email)
        tokenExpiries.removeValue(forKey: email)
        let d = UserDefaults.standard
        d.removeObject(forKey: tKey("access", email))
        d.removeObject(forKey: tKey("refresh", email))
        d.removeObject(forKey: tKey("expiry", email))
        connectedEmails.removeAll { $0 == email }
        d.set(connectedEmails, forKey: kEmails)
    }

    func signOut() {
        connectedEmails.forEach { signOut(email: $0) }
    }

    // MARK: - Private

    private func fetchUserEmail(token: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else { throw AuthError.noEmail }
        return email
    }

    private func postToken(_ body: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func pkce() -> (verifier: String, challenge: String) {
        var buf = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        let verifier  = Data(buf).base64url
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64url
        return (verifier, challenge)
    }

    private func tKey(_ type: String, _ email: String) -> String { "missting.\(type).\(email)" }

    private func save(for email: String) {
        let d = UserDefaults.standard
        if let t = accessTokens[email]  { d.set(t, forKey: tKey("access", email)) }
        if let t = refreshTokens[email] { d.set(t, forKey: tKey("refresh", email)) }
        if let e = tokenExpiries[email] { d.set(e.timeIntervalSince1970, forKey: tKey("expiry", email)) }
        d.set(connectedEmails, forKey: kEmails)
    }

    private func loadAll() {
        let d = UserDefaults.standard
        let emails = d.stringArray(forKey: kEmails) ?? []
        for email in emails {
            accessTokens[email]  = d.string(forKey: tKey("access", email))
            refreshTokens[email] = d.string(forKey: tKey("refresh", email))
            if let v = d.object(forKey: tKey("expiry", email)) as? Double {
                tokenExpiries[email] = Date(timeIntervalSince1970: v)
            }
        }
        connectedEmails = emails.filter { refreshTokens[$0] != nil }
    }

    // Migrates the old single-account storage to per-email keys.
    private func migrateIfNeeded() {
        let d = UserDefaults.standard
        guard let email = d.string(forKey: "missting.userEmail"),
              d.string(forKey: "missting.refreshToken") != nil else { return }
        if let v = d.string(forKey: "missting.accessToken")  { d.set(v, forKey: tKey("access", email)) }
        if let v = d.string(forKey: "missting.refreshToken") { d.set(v, forKey: tKey("refresh", email)) }
        if let v = d.object(forKey: "missting.tokenExpiry") as? Double { d.set(v, forKey: tKey("expiry", email)) }
        var emails = d.stringArray(forKey: kEmails) ?? []
        if !emails.contains(email) { emails.insert(email, at: 0) }
        d.set(emails, forKey: kEmails)
        ["missting.accessToken", "missting.refreshToken", "missting.tokenExpiry", "missting.userEmail"]
            .forEach { d.removeObject(forKey: $0) }
    }

    enum AuthError: Error { case noCode, notSignedIn, noEmail }
}

extension GoogleAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first ?? NSWindow()
    }
}

private struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
}

private extension Data {
    var base64url: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
