//
//  DownloadStatusView.swift
//  BiffDownload
//

import SwiftUI

struct DownloadStatusView: View {
    @ObservedObject var viewModel: DownloadFlowViewModel
    @State private var metadataStartDate: Date?

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
                    if let info = viewModel.downloadInfo, info.isFinalizationCompleted {
                        if info.canDeleteTempFiles || viewModel.isDeletingTempFiles {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteTempFiles()
                                }
                            } label: {
                                Label(
                                    viewModel.isDeletingTempFiles ? "Deleting Temp Files…" : "Delete Temp Files",
                                    systemImage: "trash"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(viewModel.isDeletingTempFiles)
                        }

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
        .onAppear {
            if viewModel.downloadInfo?.isMetadataPhase == true && metadataStartDate == nil {
                metadataStartDate = Date()
            }
        }
        .onChange(of: viewModel.downloadInfo?.isMetadataPhase) { isMetadata in
            if isMetadata == true && metadataStartDate == nil {
                metadataStartDate = Date()
            } else if isMetadata != true {
                metadataStartDate = nil
            }
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
                    TimelineView(.periodic(from: metadataStartDate ?? .now, by: 1)) { context in
                        let elapsed = Int(context.date.timeIntervalSince(metadataStartDate ?? context.date))
                        Text("Resolving metadata… (\(elapsed)s)")
                            .font(.body)
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
            } else if info.isFinalizationInProgress {
                finalizationProgressSection(info: info)
            } else if info.isAwaitingFinalization {
                finalizationReadySection(info: info)
            } else if !info.isError && !info.isFinalizationError {
                downloadProgressSection(info: info)
            }

            if info.isFinalizationCompleted {
                Text(info.finalization?.message ?? "Selected video copied to the destination folder.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.green)
            } else if info.isFinalizationInProgress {
                Text(info.finalization?.message ?? "Copying selected video to the destination folder…")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.green)
            } else if info.isAwaitingFinalization {
                Text(info.finalization?.message ?? "Download data is complete. Preparing the final copy…")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.green)
            } else if info.isFinalizationError {
                Text(info.finalization?.message ?? "Could not copy the selected video to the destination folder.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
            } else if info.isError {
                Text("Download failed.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
            }

            if info.isCleanupCompleted {
                Text(info.cleanup?.message ?? "Temp torrent files deleted.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.green)
            } else if info.isCleanupError {
                Text(info.cleanup?.message ?? "Could not delete temp files.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
            }

            destinationDetails(
                targetDirectory: info.finalization?.targetDirectory ?? info.displayDirectory ?? viewModel.queuedDirectory,
                renameTarget: info.fileSelection?.renameTarget?.fileName ?? viewModel.queuedFileName,
                destinationPath: info.finalization?.destinationPath,
                finalPath: info.finalization?.finalPath,
                finalizationMessage: nil
            )
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Waiting for download status…")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
            }

            destinationDetails(
                targetDirectory: viewModel.queuedDirectory,
                renameTarget: viewModel.queuedFileName,
                destinationPath: nil,
                finalPath: nil,
                finalizationMessage: nil
            )
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppCardBackground())
    }

    @ViewBuilder
    private func destinationDetails(
        targetDirectory: String?,
        renameTarget: String?,
        destinationPath: String?,
        finalPath: String?,
        finalizationMessage: String?
    ) -> some View {
        let hasDetails = targetDirectory != nil
            || destinationPath != nil
            || renameTarget != nil
            || finalPath != nil
            || finalizationMessage != nil

        if hasDetails {
            VStack(alignment: .leading, spacing: 14) {
                if let targetDirectory, !targetDirectory.isEmpty {
                    detailRow(title: "Destination Folder", value: targetDirectory)
                }

                if let destinationPath, !destinationPath.isEmpty {
                    detailRow(title: "Destination File", value: destinationPath)
                }

                if let finalPath, !finalPath.isEmpty {
                    detailRow(title: "Saved As", value: finalPath)
                }

                if let renameTarget, !renameTarget.isEmpty {
                    detailRow(title: "Rename Target", value: renameTarget)
                }

                if let finalizationMessage, !finalizationMessage.isEmpty {
                    Text(finalizationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.70))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }
            )
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.48))

            Text(value)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func downloadProgressSection(info: DownloadInfo) -> some View {
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

    private func finalizationReadySection(info: DownloadInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: 1)
                .tint(.green)
                .scaleEffect(y: 2, anchor: .center)

            HStack {
                Text(info.formattedProgress)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))

                Spacer()

                Text("100%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func finalizationProgressSection(info: DownloadInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: info.finalization?.progress ?? 0)
                .tint(.green)
                .scaleEffect(y: 2, anchor: .center)

            HStack {
                Text(info.finalization?.formattedProgress ?? "Preparing copy…")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))

                Spacer()

                Text("\(Int((info.finalization?.progress ?? 0) * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func stateIcon(for info: DownloadInfo) -> String {
        if info.isMetadataPhase { return "tray.and.arrow.down.fill" }
        if info.isFinalizationError || info.isError { return "exclamationmark.triangle.fill" }
        if info.isFinalizationCompleted || info.isFinalizationInProgress || info.isAwaitingFinalization {
            return "checkmark.circle.fill"
        }
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
        if info.isMetadataPhase { return .blue }
        if info.isFinalizationError || info.isError { return .red }
        if info.isFinalizationCompleted || info.isFinalizationInProgress || info.isAwaitingFinalization {
            return .green
        }
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
        if info.isFinalizationError { return "Copy Failed" }
        if info.isFinalizationCompleted || info.isFinalizationInProgress || info.isAwaitingFinalization {
            return "Downloaded"
        }
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
