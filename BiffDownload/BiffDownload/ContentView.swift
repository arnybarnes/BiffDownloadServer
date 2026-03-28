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
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.12, blue: 0.20),
                    Color(red: 0.08, green: 0.18, blue: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(connectionModel.appName)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Local server connection")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }

                    statusCard
                    configCard

                    Button {
                        Task {
                            await connectionModel.refreshConnection()
                        }
                    } label: {
                        Label(connectionModel.isConnecting ? "Checking server..." : "Reconnect", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(connectionModel.isConnecting || !connectionModel.canConnect)
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            await connectionModel.connectOnLaunchIfNeeded()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: connectionModel.statusSymbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(connectionModel.statusColor)

                Text(connectionModel.statusTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                if connectionModel.isConnecting {
                    ProgressView()
                        .tint(.white)
                }
            }

            Text(connectionModel.statusMessage)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.82))

            Divider()
                .overlay(Color.white.opacity(0.12))

            metricRow(title: "Connected to IP", value: connectionModel.connectedIPAddress ?? "Connected, but the server did not report an IP")
            metricRow(title: "Resolved via", value: connectionModel.connectedHost ?? "No hostname or IP has responded yet")
            metricRow(title: "API URL", value: connectionModel.resolvedAPIBaseURLString ?? "Unavailable")
        }
        .padding(28)
        .background(cardBackground)
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            metricRow(title: "Config source", value: connectionModel.configSourceLabel)
            metricRow(title: "Server name", value: connectionModel.serverName)
            metricRow(title: "Discovery order", value: connectionModel.discoverySummary)
            metricRow(title: "Fallback IP", value: connectionModel.fallbackIPAddress)

            if let lastCheckedAt = connectionModel.lastCheckedAt {
                metricRow(
                    title: "Last check",
                    value: lastCheckedAt.formatted(date: .abbreviated, time: .standard)
                )
            }

            if let lastError = connectionModel.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.68))
            }
        }
        .padding(28)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.white.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
    }

    private func metricRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.50))

            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
