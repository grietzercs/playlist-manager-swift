//
//  ContentView.swift
//  playlist-manager-swift
//
//  Created by Colden on 1/30/25.
//

import SwiftUI
import SwiftData
import Alamofire
import Foundation
import AuthenticationServices

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @StateObject var viewModel = MainViewModel()

    var body: some View {
        NavigationSplitView {
            Button("Spotify") {
                print("Spotify Clicked")
                viewModel.updateDisplay(newText: "Spotify Clicked")
                Task {
                    do {
                        try await viewModel.spotifyGetFeaturedPlaylists()
                    } catch {
                        print("Experienced error: \(error)")
                    }
                    
                }
            }.padding()
            Button("Start Spotify Auth") {
                print("Starting Spotify OAuth")
                //LoginSession().startAuthSession()
                viewModel.loginButtonTap()
            }
        } detail: {
            VStack {
                Text(viewModel.textDisplay).padding()
                Text(viewModel.uiState.statusText ?? "Default Status")
            }
            
            
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
