//
//  AIView.swift
//  BiffDownload
//

import SwiftUI

struct AIView: View {
    @ObservedObject var connectionModel: ServerConnectionViewModel
    @StateObject private var viewModel = AIViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                VStack(alignment: .leading, spacing: 24) {
                    header

                    if connectionModel.isConnected {
                        aiContent
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
            .onChange(of: connectionModel.resolvedAPIBaseURL) {
                Task {
                    await configureAndLoadIfNeeded(forceReload: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI")
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
                        await viewModel.refreshMacServiceStatus()
                    }
                } label: {
                    Label(viewModel.isLoadingFiles ? "Loading..." : "Refresh", systemImage: "arrow.clockwise")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!connectionModel.isConnected || viewModel.isLoadingFiles || viewModel.isWorking || viewModel.isRefreshingService)
            }
        }
    }

    private var aiContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = viewModel.errorMessage {
                messageCard(error, isError: true)
            }

            if let status = viewModel.statusMessage {
                messageCard(status, isError: false)
            }

            HStack(alignment: .top, spacing: 24) {
                generationPanel
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

    private var generationPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            macServiceCard

            Text("Uses automatic language detection on the Mac helper, creates a `.generated.srt` beside the selected video, and muxes a new subtitled copy on the download server.")
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.60))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    await viewModel.generateSubtitles()
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isGeneratingSubtitles {
                        ProgressView()
                            .tint(.white)
                    }
                    Label(viewModel.primaryActionTitle, systemImage: "sparkles")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                viewModel.isWorking
                || viewModel.selectedVideo == nil
                || (viewModel.macServiceStatus?.online == false && viewModel.serviceErrorMessage == nil)
            )
        }
        .padding(24)
        .background(AppCardBackground())
    }

    private var macServiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(macStatusColor)
                    .frame(width: 12, height: 12)

                Text(macStatusTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                if viewModel.isRefreshingService {
                    ProgressView()
                        .tint(.white)
                }
            }

            Text(macStatusSubtitle)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            if let service = viewModel.macServiceStatus {
                if let baseURL = service.baseUrl, !baseURL.isEmpty {
                    detailRow(title: "Base URL", value: baseURL)
                }

                if let lastSeen = service.lastSeen, !lastSeen.isEmpty {
                    detailRow(title: "Last Seen", value: lastSeen)
                }

                if let healthError = service.healthError, !healthError.isEmpty {
                    detailRow(title: "Health Error", value: healthError)
                }
            } else if let serviceError = viewModel.serviceErrorMessage {
                detailRow(title: "Status", value: serviceError)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(macStatusColor.opacity(0.35), lineWidth: 1)
                }
        )
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
                                AIFileEntryRow(
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
                Image(systemName: "sparkles.tv")
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

                if let subtitlePath = viewModel.generatedSubtitlePath {
                    detailRow(title: "Generated Subtitle", value: subtitlePath)
                }

                if let outputVideoPath = viewModel.outputVideoPath {
                    detailRow(title: "Output", value: outputVideoPath)
                }

                if let detectedLanguage = viewModel.detectedLanguage, !detectedLanguage.isEmpty {
                    detailRow(title: "Detected Language", value: detectedLanguage)
                }

                if let segmentCount = viewModel.segmentCount {
                    detailRow(title: "Segments", value: "\(segmentCount)")
                }

                if let transcriptionModel = viewModel.transcriptionModel, !transcriptionModel.isEmpty {
                    detailRow(title: "Model", value: transcriptionModel)
                }
            } else {
                Image(systemName: "sparkles")
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

            Text("Connect to the LAN server before generating subtitles with the Mac service.")
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

    private var macStatusColor: Color {
        if viewModel.serviceErrorMessage != nil {
            return Color(red: 1.0, green: 0.45, blue: 0.40)
        }
        guard let service = viewModel.macServiceStatus else {
            return Color.white.opacity(0.55)
        }
        if service.online == true {
            return .green
        }
        if service.registered == true {
            return .orange
        }
        return Color.white.opacity(0.55)
    }

    private var macStatusTitle: String {
        if viewModel.isRefreshingService && viewModel.macServiceStatus == nil {
            return "Checking Mac Service"
        }
        if viewModel.serviceErrorMessage != nil {
            return "Mac Service Unreachable"
        }
        guard let service = viewModel.macServiceStatus else {
            return "Mac Service Unknown"
        }
        if service.online == true {
            return "Mac Service Online"
        }
        if service.registered == true {
            return "Mac Service Offline"
        }
        return "Mac Service Not Registered"
    }

    private var macStatusSubtitle: String {
        if let serviceError = viewModel.serviceErrorMessage {
            return serviceError
        }
        guard let service = viewModel.macServiceStatus else {
            return "Refresh to check whether the Mac subtitle helper has registered with the API."
        }
        if service.online == true {
            if let hostname = service.hostname, !hostname.isEmpty {
                return "\(hostname) is online and ready to transcribe."
            }
            return "The Mac subtitle helper is online and ready to transcribe."
        }
        if service.registered == true {
            if let healthError = service.healthError, !healthError.isEmpty {
                return healthError
            }
            return "The Mac subtitle helper is registered, but its health endpoint is not responding."
        }
        return "The Windows API has not seen the Mac subtitle helper register yet."
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
        await viewModel.refreshMacServiceStatus()
    }
}

private struct AIFileEntryRow: View {
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
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(Color.white.opacity(0.58))
    }
}
