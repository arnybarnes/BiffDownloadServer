//
//  ContentView.swift
//  BiffDownload
//
//  Created by Arnold Biffna on 3/28/26.
//

import SwiftUI

struct ContentView: View {
    private enum MainTab: Hashable {
        case download
        case subtitles
        case files
        case info
        case ai
    }

    @StateObject private var connectionModel = ServerConnectionViewModel()
    @StateObject private var flowModel = DownloadFlowViewModel()
    @StateObject private var filesModel = FilesViewModel()
    @StateObject private var infoModel = InfoViewModel()
    @State private var selectedTab: MainTab = .download
    @State private var showingSearch = false
    @Namespace private var searchButton

    var body: some View {
        TabView(selection: $selectedTab) {
            downloadTab
                .tabItem {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .tag(MainTab.download)

            SubtitlesView(connectionModel: connectionModel)
                .tabItem {
                    Label("Subtitles", systemImage: "captions.bubble")
                }
                .tag(MainTab.subtitles)

            FilesView(connectionModel: connectionModel, viewModel: filesModel)
                .tabItem {
                    Label("Files", systemImage: "folder")
                }
                .tag(MainTab.files)

            InfoView(
                connectionModel: connectionModel,
                viewModel: infoModel,
                isActive: selectedTab == .info
            )
            .tabItem {
                Label("Info", systemImage: "info.circle")
            }
            .tag(MainTab.info)

            AIView(connectionModel: connectionModel)
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
                .tag(MainTab.ai)
        }
        .task {
            await connectionModel.connectOnLaunchIfNeeded()
        }
    }

    private var downloadTab: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.08)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

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

                    HStack(spacing: 20) {
                        Button {
                            guard connectionModel.isConnected else { return }
                            configureFlowModel()
                            showingSearch = true
                        } label: {
                            HStack(spacing: 10) {
                                if connectionModel.isConnecting {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Label(
                                    connectionModel.isConnecting ? "Connecting…" : "Search",
                                    systemImage: connectionModel.isConnecting ? "dot.radiowaves.left.and.right" : "magnifyingglass"
                                )
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .opacity(connectionModel.isConnected || connectionModel.isConnecting ? 1.0 : 0.4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .prefersDefaultFocus(in: searchButton)

                        NavigationLink {
                            ConnectionView(connectionModel: connectionModel)
                        } label: {
                            Label("Connection", systemImage: "network")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focusScope(searchButton)
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showingSearch) {
                DownloadFlowContainerView(viewModel: flowModel, dismiss: {
                    showingSearch = false
                })
            }
        }
    }

    private func configureFlowModel() {
        if let baseURL = connectionModel.resolvedAPIBaseURL {
            let interval = TimeInterval(loadPollingInterval())
            flowModel.configure(baseURL: baseURL, pollingInterval: interval)
        }
        flowModel.newSearch()
    }

    private func loadPollingInterval() -> Int {
        let loader = AppConfigLoader()
        if let loaded = try? loader.load() {
            return loaded.config.polling.downloadStatusIntervalSeconds
        }
        return 2
    }
}

// MARK: - Tabs

private struct PlaceholderTabView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                VStack(spacing: 22) {
                    Image(systemName: systemImage)
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))

                    Text(title)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Flow Container

struct DownloadFlowContainerView: View {
    @ObservedObject var viewModel: DownloadFlowViewModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.flowStep {
                case .search:
                    SearchView(viewModel: viewModel)
                case .results:
                    SearchResultsView(viewModel: viewModel)
                case .destination:
                    DownloadOptionsView(viewModel: viewModel)
                case .downloading:
                    DownloadStatusView(viewModel: viewModel)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        viewModel.cancelAndReset()
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
