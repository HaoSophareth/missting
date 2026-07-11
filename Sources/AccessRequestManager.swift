import Foundation

/// Submits private-beta access requests to formsubmit.co so they land in the
/// developer's inbox, instead of asking users to email in manually.
final class AccessRequestManager {
    static let shared = AccessRequestManager()

    private let endpoint = URL(string: "https://formsubmit.co/ajax/haosophareth070@gmail.com")!

    enum RequestError: Error { case badResponse }

    func requestAccess(email: String) async throws {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let payload: [String: String] = [
            "email": email,
            "_subject": "Missting beta access request",
            "_captcha": "false",
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RequestError.badResponse
        }
    }
}
