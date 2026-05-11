//
//  InfoView.swift
//  BiffDownload
//

import SwiftUI

struct InfoView: View {
    @ObservedObject var connectionModel: ServerConnectionViewModel
    @ObservedObject var viewModel: InfoViewModel
    let isActive: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                VStack(alignment: .leading, spacing: 24) {
                    header

                    if connectionModel.isConnected {
                        infoContent
                    } else {
                        disconnectedCard
                    }

                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarHidden(true)
            .task {
                if isActive {
                    await configureAndRefresh(forceReload: true)
                }
            }
            .onChange(of: isActive) { active in
                guard active else { return }
                Task {
                    await configureAndRefresh(forceReload: true)
                }
            }
            .onChange(of: connectionModel.resolvedAPIBaseURL) { _ in
                guard isActive else { return }
                Task {
                    await configureAndRefresh(forceReload: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Info")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(connectionModel.isConnected ? "Server and storage details" : connectionModel.statusTitle)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer()

            Button {
                Task {
                    await configureAndRefresh(forceReload: true)
                }
            } label: {
                Label(viewModel.isLoading ? "Loading..." : "Refresh", systemImage: "arrow.clockwise")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!connectionModel.isConnected || viewModel.isLoading)
        }
    }

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = viewModel.errorMessage {
                messageCard(error, isError: true)
            }

            if viewModel.isLoading && viewModel.disk == nil {
                loadingCard
            } else if let disk = viewModel.disk {
                HStack(alignment: .top, spacing: 24) {
                    diskCard(disk)
                        .frame(maxWidth: .infinity)

                    serverCard
                        .frame(width: 460)
                }
            } else {
                emptyCard
            }
        }
    }

    private func diskCard(_ disk: DiskInfo) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Disk")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(disk.path)
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineLimit(2)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(disk.formattedPercentUsed)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("used")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .padding(.top, 12)

                    Spacer()
                }

                ProgressView(value: disk.usedFraction)
                    .progressViewStyle(.linear)
                    .tint(progressTint(for: disk.usedFraction))
            }

            HStack(alignment: .top, spacing: 18) {
                metricTile(title: "Free", value: disk.formattedFree)
                metricTile(title: "Used", value: disk.formattedUsed)
                metricTile(title: "Total", value: disk.formattedTotal)
            }
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Server")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            metricRow(title: "Connected to IP", value: connectionModel.connectedIPAddress ?? "Unavailable")
            metricRow(title: "Resolved via", value: connectionModel.connectedHost ?? "Unavailable")
            metricRow(title: "API URL", value: connectionModel.resolvedAPIBaseURLString ?? "Unavailable")
            metricRow(title: "Disk API", value: "GET /api/v1/disk")

            if let lastUpdatedAt = viewModel.lastUpdatedAt {
                metricRow(
                    title: "Disk refreshed",
                    value: lastUpdatedAt.formatted(date: .abbreviated, time: .standard)
                )
            }
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private var disconnectedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(connectionModel.statusTitle, systemImage: "wifi.exclamationmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text(connectionModel.statusMessage)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(AppCardBackground())
    }

    private var loadingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(.white)

            Text("Loading disk information...")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(AppCardBackground())
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Disk information unavailable", systemImage: "internaldrive")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text("Refresh to request /api/v1/disk from the connected server.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(AppCardBackground())
    }

    private func messageCard(_ message: String, isError: Bool) -> some View {
        Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(isError ? Color(red: 1.0, green: 0.82, blue: 0.80) : Color(red: 0.72, green: 1.0, blue: 0.78))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(AppCardBackground())
    }

    private func metricRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.50))

            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.52))

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
        )
    }

    private func progressTint(for fraction: Double) -> Color {
        if fraction >= 0.90 {
            return .red
        }
        if fraction >= 0.75 {
            return .orange
        }
        return .green
    }

    private func configureAndRefresh(forceReload: Bool = false) async {
        guard let baseURL = connectionModel.resolvedAPIBaseURL else {
            return
        }

        viewModel.configure(baseURL: baseURL)
        if forceReload || !viewModel.hasLoaded {
            await viewModel.refresh()
        }
    }
}

struct InfoView_Previews: PreviewProvider {
    static var previews: some View {
        InfoView(
            connectionModel: ServerConnectionViewModel(),
            viewModel: InfoViewModel(),
            isActive: true
        )
    }
}
