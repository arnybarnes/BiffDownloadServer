//
//  ContentView.swift
//  BiffDownload
//
//  Created by Arnold Biffna on 3/28/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var connectionModel = ServerConnectionViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(connectionModel.appName)
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Apple TV controller for your LAN download server")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text(connectionModel.isConnected ? "Connected to IP: \(connectionModel.connectedIPAddress ?? "Unavailable")" : connectionModel.statusTitle)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(connectionModel.statusMessage)
                            .font(.body)
                            .foregroundStyle(Color.white.opacity(0.80))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
                    .background(AppCardBackground())

                    NavigationLink {
                        ConnectionView(connectionModel: connectionModel)
                    } label: {
                        Label("Connection", systemImage: "network")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarHidden(true)
        }
        .task {
            await connectionModel.connectOnLaunchIfNeeded()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
