//
//  ConnectionView.swift
//  BiffDownload
//
//  Created by Codex on 3/28/26.
//

import SwiftUI

struct ConnectionView: View {
    @ObservedObject var connectionModel: ServerConnectionViewModel
    @State private var ipOctets = ["", "", "", ""]
    @State private var ipChangeMessage: String?
    @State private var ipChangeError: String?

    var body: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    statusBar
                    statusDetailsCard
                    configCard
                    ipEditorCard
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Connection")
        .onAppear {
            syncIPFieldsFromModel()
        }
    }

    private var statusBar: some View {
        HStack(alignment: .center, spacing: 24) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: connectionModel.statusSymbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(connectionModel.statusColor)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(connectionModel.statusTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)

                        if connectionModel.isConnecting {
                            ProgressView()
                                .tint(.white)
                        }
                    }

                    Text(connectionModel.statusMessage)
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.80))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 24)

            Button {
                Task {
                    await connectionModel.refreshConnection()
                }
            } label: {
                Label(connectionModel.isConnecting ? "Checking..." : "Reconnect", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(minWidth: 230)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(connectionModel.isConnecting || !connectionModel.canConnect)
        }
        .padding(24)
        .background(AppCardBackground())
    }

    private var statusDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricRow(title: "Connected to IP", value: connectionModel.connectedIPAddress ?? "Connected, but the server did not report an IP")
            metricRow(title: "Resolved via", value: connectionModel.connectedHost ?? "No hostname or IP has responded yet")
            metricRow(title: "API URL", value: connectionModel.resolvedAPIBaseURLString ?? "Unavailable")
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            metricRow(title: "Config source", value: connectionModel.configSourceLabel)
            metricRow(title: "Server name", value: connectionModel.serverName)
            metricRow(title: "Discovery order", value: connectionModel.discoverySummary)
            metricRow(title: "Current fallback IP", value: connectionModel.fallbackIPAddress)
            metricRow(title: "Bundled fallback IP", value: connectionModel.bundledFallbackIPAddress)
            metricRow(title: "IP override", value: connectionModel.ipOverrideStatus)

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
        .background(AppCardBackground())
    }

    private var ipEditorCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Change IP Address")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Update the saved fallback IP used after hostname discovery fails. Hostname probes still run first.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.78))

            HStack(spacing: 14) {
                ForEach(ipOctets.indices, id: \.self) { index in
                    TextField("0", text: octetBinding(for: index))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(.white.opacity(0.10), lineWidth: 1)
                                }
                        )
                        .frame(width: 110)
                }
            }

            Button {
                Task {
                    await applyIPAddressChange()
                }
            } label: {
                Text("Change IP Address")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasValidIPAddressInput || connectionModel.isConnecting)

            if let ipChangeMessage {
                Text(ipChangeMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.76))
            }

            if let ipChangeError {
                Text(ipChangeError)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
            }
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private var hasValidIPAddressInput: Bool {
        normalizedIPAddress(from: ipOctets) != nil
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

    private func octetBinding(for index: Int) -> Binding<String> {
        Binding {
            ipOctets[index]
        } set: { newValue in
            let filteredValue = newValue.filter(\.isNumber)
            ipOctets[index] = String(filteredValue.prefix(3))
            ipChangeMessage = nil
            ipChangeError = nil
        }
    }

    private func syncIPFieldsFromModel() {
        ipOctets = connectionModel.currentIPAddressOctets()
    }

    private func applyIPAddressChange() async {
        guard let ipAddress = normalizedIPAddress(from: ipOctets) else {
            ipChangeMessage = nil
            ipChangeError = "Enter four valid IPv4 octets between 0 and 255."
            return
        }

        connectionModel.setManualIPAddress(ipAddress)
        syncIPFieldsFromModel()
        ipChangeError = nil
        ipChangeMessage = "Saved fallback IP override: \(ipAddress)"
        await connectionModel.refreshConnection()
    }

    private func normalizedIPAddress(from octets: [String]) -> String? {
        guard octets.count == 4 else {
            return nil
        }

        let normalizedOctets = octets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard normalizedOctets.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }

        let validatedOctets = normalizedOctets.compactMap { octet -> String? in
            guard let value = Int(octet), (0...255).contains(value) else {
                return nil
            }

            return String(value)
        }

        guard validatedOctets.count == 4 else {
            return nil
        }

        return validatedOctets.joined(separator: ".")
    }
}

struct AppBackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.12, blue: 0.20),
                Color(red: 0.08, green: 0.18, blue: 0.16),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct AppCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.white.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
    }
}

struct ConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ConnectionView(connectionModel: ServerConnectionViewModel())
        }
    }
}
