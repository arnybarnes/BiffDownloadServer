//
//  SubtitlesView.swift
//  BiffDownload
//

import SwiftUI

struct SubtitlesView: View {
    @ObservedObject var connectionModel: ServerConnectionViewModel
    @StateObject private var viewModel = SubtitlesViewModel()
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                VStack(alignment: .leading, spacing: 24) {
                    header

                    if connectionModel.isConnected {
                        subtitlesContent
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
                await configureAndLoadIfNeeded()
            }
            .onChange(of: connectionModel.resolvedAPIBaseURL) { _ in
                Task {
                    await configureAndLoadIfNeeded(forceReload: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Subtitles")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(viewModel.pathDisplayName)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 16) {
                Button {
                    Task {
                        await viewModel.goUp()
                    }
                } label: {
                    Label("Up", systemImage: "chevron.up")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!connectionModel.isConnected || !viewModel.canGoUp || viewModel.isLoadingFiles || viewModel.isWorking)

                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Label(viewModel.isLoadingFiles ? "Loading..." : "Refresh", systemImage: "arrow.clockwise")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!connectionModel.isConnected || viewModel.isLoadingFiles || viewModel.isWorking)
            }
        }
    }

    private var subtitlesContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = viewModel.errorMessage {
                messageCard(error, isError: true)
            }

            if let status = viewModel.statusMessage {
                messageCard(status, isError: false)
            }

            HStack(alignment: .top, spacing: 24) {
                setupPanel
                    .frame(width: 520)
                    .focusSection()

                fileChooser
                    .frame(maxWidth: .infinity, maxHeight: 670)
                    .focusSection()

                selectionPanel
                    .frame(width: 430)
                    .focusSection()
            }
        }
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Search")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                TextField("Show name", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(18)
                    .background(fieldBackground)
                    .focused($isSearchFieldFocused)
            }

            Toggle("Append episode", isOn: $viewModel.appendEpisode)
                .font(.body)

            if viewModel.appendEpisode {
                VStack(alignment: .leading, spacing: 18) {
                    subtitleStepper(
                        title: "Season",
                        value: viewModel.seasonNumber,
                        decrement: {
                            if viewModel.seasonNumber > 1 { viewModel.seasonNumber -= 1 }
                        },
                        increment: {
                            viewModel.seasonNumber += 1
                        },
                        decrementDisabled: viewModel.seasonNumber <= 1
                    )

                    subtitleStepper(
                        title: "Episode",
                        value: viewModel.episodeNumber,
                        decrement: {
                            if viewModel.episodeNumber > 1 { viewModel.episodeNumber -= 1 }
                        },
                        increment: {
                            viewModel.episodeNumber += 1
                        },
                        decrementDisabled: viewModel.episodeNumber <= 1
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Language")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.52))

                TextField("en", text: $viewModel.language)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .padding(16)
                    .background(fieldBackground)
            }

            if !viewModel.fullSearchName.isEmpty {
                Text("Will search: \(viewModel.fullSearchName)")
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(2)
            }

            Button {
                Task {
                    await viewModel.applySubtitle()
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isWorking {
                        ProgressView()
                            .tint(.white)
                    }
                    Label(viewModel.primaryActionTitle, systemImage: "captions.bubble")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                viewModel.isWorking
                || viewModel.fullSearchName.isEmpty
                || viewModel.selectedVideo == nil
            )
        }
        .padding(24)
        .background(AppCardBackground())
        .onAppear {
            isSearchFieldFocused = true
        }
    }

    private var fileChooser: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "folder")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.absolutePath ?? viewModel.root ?? "Download root")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("\(viewModel.visibleEntries.count) selectable item\(viewModel.visibleEntries.count == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.68))
                }

                Spacer()

                if viewModel.isLoadingFiles {
                    ProgressView()
                        .tint(.white)
                }
            }
            .padding(22)
            .background(AppCardBackground())

            if viewModel.isLoadingFiles && viewModel.entries.isEmpty {
                loadingCard
            } else if viewModel.visibleEntries.isEmpty {
                emptyFolderCard
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.visibleEntries) { entry in
                            Button {
                                if entry.isDirectory {
                                    Task {
                                        await viewModel.openFolder(entry)
                                    }
                                } else {
                                    viewModel.selectVideo(entry)
                                }
                            } label: {
                                SubtitleFileEntryRow(
                                    entry: entry,
                                    isSelected: viewModel.selectedVideo?.id == entry.id
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isWorking)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let video = viewModel.selectedVideo {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                VStack(alignment: .leading, spacing: 8) {
                    Text(video.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(4)

                    detailRow(title: "Path", value: video.relativePath)
                    detailRow(title: "Size", value: video.formattedSize)
                    detailRow(title: "Modified", value: video.formattedModifiedAt)
                }

                if let subtitlePath = viewModel.downloadedSubtitlePath {
                    detailRow(title: "Subtitle", value: subtitlePath)
                }

                if let outputVideoPath = viewModel.outputVideoPath {
                    detailRow(title: "Output", value: outputVideoPath)
                }
            } else {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Text("No Video Selected")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Pick a video file from the browser.")
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .padding(24)
        .background(AppCardBackground())
    }

    private var disconnectedCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Not Connected", systemImage: "network.slash")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Connect to the LAN server before downloading subtitles.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.76))

            NavigationLink {
                ConnectionView(connectionModel: connectionModel)
            } label: {
                Label("Connection", systemImage: "network")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Loading files...")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(AppCardBackground())
    }

    private var emptyFolderCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Text("No videos here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .background(AppCardBackground())
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.white.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
    }

    private func subtitleStepper(
        title: String,
        value: Int,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        decrementDisabled: Bool
    ) -> some View {
        HStack(spacing: 28) {
            Text(title)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 78, alignment: .leading)

            Button(action: decrement) {
                SubtitleStepperButtonLabel(systemImage: "minus")
            }
            .buttonStyle(.plain)
            .disabled(decrementDisabled)

            Text("\(value)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(minWidth: 50)

            Button(action: increment) {
                SubtitleStepperButtonLabel(systemImage: "plus")
            }
            .buttonStyle(.plain)
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
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageCard(_ message: String, isError: Bool) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(isError ? Color(red: 1.0, green: 0.82, blue: 0.80) : .green)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppCardBackground())
    }

    private func configureAndLoadIfNeeded(forceReload: Bool = false) async {
        guard connectionModel.isConnected,
              let baseURL = connectionModel.resolvedAPIBaseURL else {
            return
        }

        viewModel.configure(baseURL: baseURL)

        if forceReload || !viewModel.hasLoaded {
            await viewModel.loadRoot()
        }
    }
}

private struct SubtitleStepperButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: "\(systemImage).circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.12), .white)
            .font(.title2.weight(.semibold))
    }
}

private struct SubtitleFileEntryRow: View {
    let entry: FileEntry
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "play.rectangle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.80))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 7) {
                Text(entry.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 16) {
                    label(icon: entry.isDirectory ? "folder" : "doc", text: entry.formattedSize)
                    label(icon: "clock", text: entry.formattedModifiedAt)
                }
            }

            Spacer(minLength: 12)

            Image(systemName: entry.isDirectory ? "chevron.right" : selectedIcon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(entry.isDirectory || isSelected ? 0.72 : 0.36))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(borderColor, lineWidth: isFocused || isSelected ? 2 : 1)
                }
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var selectedIcon: String {
        isSelected ? "checkmark.circle.fill" : "circle"
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

    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.50))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
        }
    }
}
