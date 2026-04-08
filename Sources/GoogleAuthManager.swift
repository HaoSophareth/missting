import Foundation
import AuthenticationServices
import CryptoKit
import AppKit

final class GoogleAuthManager: NSObject, ObservableObject {
    static let shared = GoogleAuthManager()

    private let clientId     = "267510202208-v3f2f0fsouhptgh62hphus7t4hhppf0i.apps.googleusercontent.com"
    // Reverse-DNS of the client ID — registered as redirect URI in Google Cloud Console
    private let redirectScheme = "com.googleusercontent.apps.267510202208-v3f2f0fsouhptgh62hphus7t4hhppf0i"
    // calendar.events allows both reading and writing (needed for RSVP)
    private let scope = "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly"

    @Published var isSignedIn = false
    @Published var userEmail: String?

    private var accessToken:  String?
    private var refreshToken: String?
    private var tokenExpiry:  Date?

    private let kAccess  = "missting.accessToken"
    private let kRefresh = "missting.refreshToken"
    private let kExpiry  = "missting.tokenExpiry"
    private let kEmail   = "missting.userEmail"

    override init() {
        super.init()
        loadKeychain()
    }

    // MARK: - Public

    func signIn() async throws {
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
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        try await exchange(code: code, verifier: verifier)
        await fetchUserEmail()
    }

    func getValidToken() async throws -> String {
        if let t = accessToken, let exp = tokenExpiry, exp > Date().addingTimeInterval(60) {
            return t
        }
        if let rt = refreshToken {
            try await refresh(rt)
            if let t = accessToken { return t }
        }
        throw AuthError.notSignedIn
    }

    func signOut() {
        accessToken = nil; refreshToken = nil; tokenExpiry = nil; userEmail = nil
        isSignedIn  = false
        [kAccess, kRefresh, kExpiry, kEmail].forEach(deleteKeychain)
    }

    private func fetchUserEmail() async {
        guard let token = accessToken else { return }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else { return }
        await MainActor.run {
            userEmail = email
            UserDefaults.standard.set(email, forKey: kEmail)
        }
    }

    // MARK: - PKCE

    private func pkce() -> (verifier: String, challenge: String) {
        var buf = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        let verifier  = Data(buf).base64url
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64url
        return (verifier, challenge)
    }

    // MARK: - Token exchange

    private func exchange(code: String, verifier: String) async throws {
        let body: [String: String] = [
            "client_id":     clientId,
            "code":          code,
            "code_verifier": verifier,
            "grant_type":    "authorization_code",
            "redirect_uri":  "\(redirectScheme):/oauth2callback",
        ]
        try await postToken(body)
    }

    private func refresh(_ rt: String) async throws {
        let body: [String: String] = [
            "client_id":     clientId,
            "refresh_token": rt,
            "grant_type":    "refresh_token",
        ]
        try await postToken(body)
    }

    private func postToken(_ body: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let tok = try JSONDecoder().decode(TokenResponse.self, from: data)

        await MainActor.run {
            accessToken  = tok.access_token
            tokenExpiry  = Date().addingTimeInterval(TimeInterval(tok.expires_in ?? 3600))
            if let rt = tok.refresh_token { refreshToken = rt }
            isSignedIn   = true
            UserDefaults.standard.set(tok.access_token, forKey: kAccess)
            if let rt = tok.refresh_token { UserDefaults.standard.set(rt, forKey: kRefresh) }
            if let exp = tokenExpiry { UserDefaults.standard.set(exp.timeIntervalSince1970, forKey: kExpiry) }
        }
    }

    // MARK: - UserDefaults storage (no password prompts)

    private func loadKeychain() {
        let d = UserDefaults.standard
        accessToken  = d.string(forKey: kAccess)
        refreshToken = d.string(forKey: kRefresh)
        if let v = d.object(forKey: kExpiry) as? Double {
            tokenExpiry = Date(timeIntervalSince1970: v)
        }
        isSignedIn = refreshToken != nil
        userEmail  = d.string(forKey: kEmail)
    }

    private func saveKeychain(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func deleteKeychain(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Errors

    enum AuthError: Error {
        case noCode, notSignedIn
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first ?? NSWindow()
    }
}

// MARK: - Helpers

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
