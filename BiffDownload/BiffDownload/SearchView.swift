//
//  SearchView.swift
//  BiffDownload
//

import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: DownloadFlowViewModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Search")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Find something to download")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                VStack(alignment: .leading, spacing: 20) {
                    TextField("Enter search term…", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.white.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                }
                        )
                        .focused($isSearchFieldFocused)

                    Toggle("Append episode", isOn: $viewModel.appendEpisode)
                        .font(.body)

                    if viewModel.appendEpisode {
                        HStack(spacing: 24) {
                            HStack(spacing: 10) {
                                Text("Season")
                                    .font(.body)
                                    .foregroundStyle(Color.white.opacity(0.72))
                                Button {
                                    if viewModel.seasonNumber > 1 { viewModel.seasonNumber -= 1 }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .disabled(viewModel.seasonNumber <= 1)

                                Text("\(viewModel.seasonNumber)")
                                    .font(.headline)
                                    .frame(minWidth: 40)

                                Button {
                                    viewModel.seasonNumber += 1
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                            }

                            HStack(spacing: 10) {
                                Text("Episode")
                                    .font(.body)
                                    .foregroundStyle(Color.white.opacity(0.72))
                                Button {
                                    if viewModel.episodeNumber > 1 { viewModel.episodeNumber -= 1 }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .disabled(viewModel.episodeNumber <= 1)

                                Text("\(viewModel.episodeNumber)")
                                    .font(.headline)
                                    .frame(minWidth: 40)

                                Button {
                                    viewModel.episodeNumber += 1
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                            }
                        }
                    }

                    Toggle("Append 1080p x265", isOn: $viewModel.appendSuffix)
                        .font(.body)

                    if !viewModel.fullQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Will search: \(viewModel.fullQuery)")
                            .font(.callout)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(28)
                .background(AppCardBackground())

                HStack(spacing: 20) {
                    Button {
                        Task { await viewModel.performSearch() }
                    } label: {
                        HStack(spacing: 10) {
                            if viewModel.isSearching {
                                ProgressView()
                                    .tint(.white)
                            }
                            Label(
                                viewModel.isSearching ? "Searching…" : "Search",
                                systemImage: "magnifyingglass"
                            )
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        viewModel.isSearching
                        || viewModel.fullQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if let error = viewModel.searchError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppCardBackground())
                }

                Spacer()
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            isSearchFieldFocused = true
        }
    }
}
