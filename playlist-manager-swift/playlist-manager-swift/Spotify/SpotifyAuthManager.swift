//  This file was created with assistance from Claude
//  AuthManager.swift
//  playlist-manager-swift
//
//  Created by Colden on 4/9/25.
//

import AppKit
import AuthenticationServices
import CommonCrypto

// MARK: - Supporting Types

struct SpotifyToken: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    var refreshToken: String
    let scope: String
    private let receivedAt = Date()
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
    
    var isExpired: Bool {
        let expirationDate = receivedAt.addingTimeInterval(TimeInterval(expiresIn - 60)) // Buffer of 60 seconds
        return Date() >= expirationDate
    }
}

enum SpotifyAuthError: Error, LocalizedError {
    case pkceGenerationFailed
    case invalidCallbackURL
    case noAuthorizationCode
    case noCallbackURL
    case noData
    case noToken
    case spotifyError(String)
    
    var errorDescription: String? {
        switch self {
        case .pkceGenerationFailed:
            return "Failed to generate PKCE code verifier and challenge"
        case .invalidCallbackURL:
            return "Invalid callback URL received"
        case .noAuthorizationCode:
            return "No authorization code in callback"
        case .noCallbackURL:
            return "No callback URL received"
        case .noData:
            return "No data received from server"
        case .noToken:
            return "No authentication token available"
        case .spotifyError(let message):
            return "Spotify error: \(message)"
        }
    }
}

class SpotifyAuthManager: NSObject {
    // MARK: - Properties
       
    // Spotify API Configuration
    private let clientId: String
    private let redirectUri: String
    private let scopes: [String]

    // PKCE-specific properties
    private var codeVerifier: String?
    private var codeChallenge: String?

    // Authentication state
    private var authSession: ASWebAuthenticationSession?
    private var completionHandler: ((Result<SpotifyToken, Error>) -> Void)?

    // Auth session state
    private var currentToken: SpotifyToken?
    
    init(scopes: [String] = ["user-read-private", "user-read-email"]) {
        self.clientId = EnvironmentManager.shared.string(for: "SPOTIFY_CLIENT_ID") ?? ""
        self.redirectUri = EnvironmentManager.shared.string(for: "BUNDLE_SCHEME") ?? "" + "://callback"
        self.scopes = ["user-read-email", "user-read-recently-played", "playlist-modify-private", "playlist-modify-public", "user-library-modify"]
        super.init()
    }
    
    // MARK: - PKCE Helpers
    private func generatePKCECodes() {
        // Generate a random 128-byte verifier string
        var buffer = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        codeVerifier = Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        // Create the code challenge by hashing the verifier with SHA256 and base64url encoding
        if let verifier = codeVerifier, let data = verifier.data(using: .utf8) {
            var buffer = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes {
                _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &buffer)
            }
            
            codeChallenge = Data(buffer).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
    }
    
    // MARK: - URL Handling
    
    private func buildAuthorizationURL(codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            // This makes the user re-approve each time - in production you might want to remove this
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        
        return components.url!
    }
    
    private func extractCallbackScheme() -> String {
        // Extract the URL scheme from the redirect URI
        guard let url = URL(string: redirectUri) else { return "" }
        return url.scheme ?? ""
    }
    
    // MARK: - Public Methods
    
    func authorize(completion: @escaping (Result<SpotifyToken, Error>) -> Void) {
        self.completionHandler = completion
        
        // Generate PKCE code verifier and challenge
        generatePKCECodes()
        
        guard let codeChallenge = codeChallenge else {
            completion(.failure(SpotifyAuthError.pkceGenerationFailed))
            return
        }
        
        // Build the authorization URL with PKCE parameters
        let authURL = buildAuthorizationURL(codeChallenge: codeChallenge)
        
        // Present the authentication session
        let authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: extractCallbackScheme(),
            completionHandler: { [weak self] callbackURL, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.completionHandler?(.failure(error))
                    self.completionHandler = nil
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    self.completionHandler?(.failure(SpotifyAuthError.noCallbackURL))
                    self.completionHandler = nil
                    return
                }
                
                self.handleAuthCallback(url: callbackURL)
            }
        )
        
        // Set presentationContextProvider if needed for better UX on macOS
        if let window = NSApplication.shared.keyWindow {
            authSession.presentationContextProvider = self
        }
        
        // Start the auth session
        authSession.start()
        self.authSession = authSession
    }
        
    func refreshTokenIfNeeded(completion: @escaping (Result<SpotifyToken, Error>) -> Void) {
        guard let currentToken = currentToken, currentToken.isExpired else {
            // Token is still valid
            if let token = currentToken {
                completion(.success(token))
            } else {
                completion(.failure(SpotifyAuthError.noToken))
            }
            return
        }
        
        // Perform token refresh
        refreshToken(currentToken.refreshToken, completion: completion)
    }
    
    // MARK: - Token Management
    
    private func exchangeCodeForToken(_ code: String, completion: @escaping (Result<SpotifyToken, Error>) -> Void) {
        guard let codeVerifier = codeVerifier else {
            completion(.failure(SpotifyAuthError.pkceGenerationFailed))
            return
        }
        
        // Create token exchange request
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Set request headers
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Set request body parameters
        let bodyParameters = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
            "code_verifier": codeVerifier
        ]
        request.httpBody = bodyParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        // Make the request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(SpotifyAuthError.noData))
                }
                return
            }
            
            do {
                let token = try JSONDecoder().decode(SpotifyToken.self, from: data)
                self.currentToken = token
                DispatchQueue.main.async {
                    completion(.success(token))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    private func refreshToken(_ refreshToken: String, completion: @escaping (Result<SpotifyToken, Error>) -> Void) {
        // Create token refresh request
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Set request headers
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Set request body parameters
        let bodyParameters = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = bodyParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        // Make the request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(SpotifyAuthError.noData))
                }
                return
            }
            
            do {
                var token = try JSONDecoder().decode(SpotifyToken.self, from: data)
                
                // The refresh endpoint doesn't return a refresh token, so we need to keep the old one
                if token.refreshToken.isEmpty {
                    token.refreshToken = refreshToken
                }
                
                self.currentToken = token
                DispatchQueue.main.async {
                    completion(.success(token))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    private func handleAuthCallback(url: URL) {
        // Extract the authorization code from the callback URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            completionHandler?(.failure(SpotifyAuthError.invalidCallbackURL))
            completionHandler = nil
            return
        }
        
        // Check if there was an error
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            completionHandler?(.failure(SpotifyAuthError.spotifyError(error)))
            completionHandler = nil
            return
        }
        
        // Extract the code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            completionHandler?(.failure(SpotifyAuthError.noAuthorizationCode))
            completionHandler = nil
            return
        }
        
        // Exchange the code for a token
        if let completionHandler = completionHandler {
            exchangeCodeForToken(code, completion: completionHandler)
        }
        self.completionHandler = nil
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SpotifyAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow ?? NSWindow()
    }
}


