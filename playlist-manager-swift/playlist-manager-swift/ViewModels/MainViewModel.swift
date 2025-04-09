//
//  MainViewModel.swift
//  playlist-manager-swift
//
//  Created by Colden on 2/12/25.
//

import Foundation
import SwiftUI
import Alamofire
import AuthenticationServices

struct UIState {
    var isLoading: Bool = false
    var error: String? = nil
    var service: String? = nil
    var statusText: String? = nil
    var spotifyLoginButtonText: String? = "Login"
}

class MainViewModel: ObservableObject {
    @Published private(set) var uiState = UIState()
    
    var textDisplay: String = "Default Text"
    @Published var startWebAuthSession: Bool = false
    private var spotifyAuthManager: SpotifyAuthManager
    
    init() {
        spotifyAuthManager = SpotifyAuthManager()
    }
    
    func updateDisplay(newText: String) {
        textDisplay = newText
    }
    
    // temporary auth handler
    func getSpotifyAuthToken() async throws  -> String {
        let jwtToken = try SpotifyAuthenticator.getJWToken()
        //let request = try SpotifyAuthenticator.getRequestShell(token: jwtToken)
        //let data = try await NetworkManager.sendRequest(urlRequest: request)
        //print(data)
        let params = [
            "grant_type": "client_credentials",
        ]
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(jwtToken)",
            "Accept": "application/json",
            "Cotent-Type": "application/x-www-form-urlencoded"
        ]
        
        let request = AF.request("https://accounts.spotify.com/api/token", method: .post, parameters: params, encoder: URLEncodedFormParameterEncoder(destination: .httpBody), headers: headers)
        let stringResponse = await request.serializingString().response
        
        guard let accessTokenString: String = stringResponse.value else {
            //TODO
            return "" // throw error
        }
        
        guard let accessTokenData = accessTokenString.data(using: .utf8) else {
            //TODO
            return "" // throw error
        }
        let access_token = try JSONDecoder().decode(AuthResponse.self, from: accessTokenData)
        return access_token.accessToken ?? ""
    }
    
    func loginButtonTap() {
        uiState.statusText = "Logging into Spotify"
        spotifyAuthManager.authorize { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let token):
                uiState.statusText = "Logged in successfully"
                uiState.spotifyLoginButtonText = "Refresh Token"
                Task {
                    await self.fetchUserProfile(token: token.accessToken)
                }
            case .failure(let error):
                uiState.statusText = "Login failed: \(error.localizedDescription)"
                uiState.error = "Failed to login"
            }
            
            
        }
    }
    
    func fetchUserProfile(token: String) async {
        // Create the request to get user profile data
        guard let url = URL(string: "https://api.spotify.com/v1/me") else {
            uiState.error = "Failed to set URL string for user profile"
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let displayName = json?["display_name"] as? String
            let email = json?["email"] as? String
            
            uiState.statusText = "DisplayName: \(displayName) Email: \(email)"
        } catch {
            DispatchQueue.main.async {
                self.uiState.error = "Failed to fetch user profile in async await"
                self.uiState.statusText = "Login failed: \(error.localizedDescription)"
            }
        }
        
        
    }
    
    func spotifyGetFeaturedPlaylists() async throws {
        let accessToken = try await getSpotifyAuthToken()
        
        let urlString = "https://api.spotify.com/v1/browse/new-releases"
        var request: URLRequest = try URLRequest(url: urlString, method: .get)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: (Data, URLResponse) = try await URLSession.shared.data(for: request)
        print("Feaured playlists data: ", response)
    }
    
    func startAuthFlow() async throws {
        print("Starting auth flow function")
        // Use the URL and callback scheme specified by the authorization provider
        guard let authURL = URL(string: "https://accounts.spotify.com/authorize") else {
            return
        }
        let scheme = "playlist-manager"
        
        print("Reached ASWebAuthenticationSession")
        // Initialize the session
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { callbackURL, error in
            print("Callback received")
        }
        session.start()
    }
    
    func spotifyLogin() {
        
    }
    
//    func spotifyLibraryAuth() {
//        let configuration = SPTConfiguration(
//            clientID: ''
//        )
//    }
}

class LoginSession: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    var webAuthSession: ASWebAuthenticationSession?
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
    
    func startAuthSession() {
        webAuthSession = ASWebAuthenticationSession.init(url: URL(string: "https://accounts.spotify.com/authorize")!, callbackURLScheme: "playlistmanager", completionHandler: { (callback: URL?, error: Error?) in
            if (error != nil) {
                print("Error description: ", error.debugDescription)
            }
            print("You are now logged in")
        })
        
        webAuthSession?.presentationContextProvider = self
        webAuthSession?.prefersEphemeralWebBrowserSession = true
        webAuthSession?.start()
    }
}
