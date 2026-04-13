//
//  DownloadOptionsView.swift
//  BiffDownload
//

import SwiftUI

struct DownloadOptionsView: View {
    @ObservedObject var viewModel: DownloadFlowViewModel

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download Options")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Pick the destination folder before the download request is sent.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }

                    Spacer()

                    Button {
                        viewModel.backToResults()
                    } label: {
                        Label("Back to Results", systemImage: "chevron.left")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isQueueing)
                }

                if let selectedResult = viewModel.selectedResult {
                    selectedResultCard(selectedResult)
                }

                destinationCard

                if let error = viewModel.downloadError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppCardBackground())
                }

                HStack(spacing: 20) {
                    Button {
                        viewModel.backToResults()
                    } label: {
                        Label("Choose Another File", systemImage: "list.bullet")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isQueueing)

                    Button {
                        Task { await viewModel.queueSelectedResult() }
                    } label: {
                        if viewModel.isQueueing {
                            HStack(spacing: 12) {
                                ProgressView().tint(.white)
                                Text("Queuing Download…")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Start Download", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isQueueing || viewModel.selectedResult == nil)
                }

                Spacer()
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectedResultCard(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Selected File")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text(result.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(3)

            HStack(spacing: 16) {
                optionLabel(icon: "doc", text: result.formattedSize)
                if let indexer = result.indexer {
                    optionLabel(icon: "building.2", text: indexer)
                }
                if let seeders = result.seeders {
                    optionLabel(icon: "arrow.up", text: "\(seeders)")
                }
                if let leechers = result.leechers {
                    optionLabel(icon: "arrow.down", text: "\(leechers)")
                }
            }
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Destination Folder")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(viewModel.selectedDownloadFolder?.subtitle ?? "Default download root")
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(2)
                }

                Spacer()

                if viewModel.isLoadingFolders {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Loading folders…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
            }

            if let renameSummary = viewModel.episodeRenameSummary {
                Label(renameSummary, systemImage: "textformat")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.82))
            }

            if let folderError = viewModel.folderLoadError {
                Text(folderError)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.downloadFolders) { folder in
                        Button {
                            viewModel.selectDownloadFolder(folder)
                        } label: {
                            DownloadFolderButton(
                                folder: folder,
                                isSelected: viewModel.selectedDownloadFolder?.id == folder.id
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isQueueing || viewModel.isLoadingFolders)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private func optionLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.50))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
        }
    }
}

private struct DownloadFolderButton: View {
    let folder: DownloadFolderChoice
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(folder.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(folder.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(borderColor, lineWidth: isFocused || isSelected ? 2 : 1)
                }
        )
        .scaleEffect(isFocused ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var backgroundColor: Color {
        if isFocused {
            return Color(red: 0.18, green: 0.32, blue: 0.48)
        }
        if isSelected {
            return Color.white.opacity(0.16)
        }
        return Color.white.opacity(0.08)
    }

    private var borderColor: Color {
        if isFocused || isSelected {
            return .white.opacity(0.28)
        }
        return .white.opacity(0.10)
    }
}
