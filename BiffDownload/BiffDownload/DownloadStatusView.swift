//
//  DownloadStatusView.swift
//  BiffDownload
//

import SwiftUI

struct DownloadStatusView: View {
    @ObservedObject var viewModel: DownloadFlowViewModel

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Download")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let selected = viewModel.selectedResult {
                        Text(selected.title)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(2)
                    }
                }

                if let info = viewModel.downloadInfo {
                    downloadCard(info: info)
                } else if viewModel.isPolling {
                    waitingCard
                }

                if let error = viewModel.downloadError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppCardBackground())
                }

                HStack(spacing: 20) {
                    if let info = viewModel.downloadInfo, info.isComplete {
                        Button {
                            viewModel.newSearch()
                        } label: {
                            Label("New Search", systemImage: "magnifyingglass")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button(role: .destructive) {
                            viewModel.cancelAndReset()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            viewModel.backToResults()
                        } label: {
                            Label("Back to Results", systemImage: "list.bullet")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func downloadCard(info: DownloadInfo) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: stateIcon(for: info))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(stateColor(for: info))

                VStack(alignment: .leading, spacing: 4) {
                    Text(stateLabel(for: info))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(info.displayName)
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }

            if info.isMetadataPhase {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Resolving metadata…")
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            } else if !info.isComplete && !info.isError {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: info.progress)
                        .tint(.blue)
                        .scaleEffect(y: 2, anchor: .center)

                    HStack {
                        Text(info.formattedProgress)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.72))

                        Spacer()

                        Text(info.formattedSpeed)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.72))

                        Spacer()

                        Text(info.estimatedTimeRemaining)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.72))

                        Spacer()

                        Text("\(Int(info.progress * 100))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }

            if info.isComplete {
                Text("Download complete.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.green)
            }

            if info.isError {
                Text("Download failed.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
            }
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private var waitingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Waiting for download status…")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(AppCardBackground())
    }

    private func stateIcon(for info: DownloadInfo) -> String {
        switch info.state {
        case "complete": return "checkmark.circle.fill"
        case "error": return "exclamationmark.triangle.fill"
        case "active": return "arrow.down.circle.fill"
        case "waiting": return "clock.fill"
        case "paused": return "pause.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private func stateColor(for info: DownloadInfo) -> Color {
        switch info.state {
        case "complete": return .green
        case "error": return .red
        case "active": return .blue
        case "waiting": return .yellow
        case "paused": return .orange
        default: return .gray
        }
    }

    private func stateLabel(for info: DownloadInfo) -> String {
        if info.isMetadataPhase { return "Resolving Metadata" }
        switch info.state {
        case "complete": return "Complete"
        case "error": return "Error"
        case "active": return "Downloading"
        case "waiting": return "Waiting"
        case "paused": return "Paused"
        case "removed": return "Removed"
        default: return info.state?.capitalized ?? "Unknown"
        }
    }
}
