//
//  SearchResultsView.swift
//  BiffDownload
//

import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var viewModel: DownloadFlowViewModel

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Results")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if let message = viewModel.searchMessage {
                            Text(message)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }

                    Spacer()

                    Button {
                        viewModel.newSearch()
                    } label: {
                        Label("New Search", systemImage: "magnifyingglass")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if viewModel.isQueueing {
                    HStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Queuing download…")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(AppCardBackground())
                }

                if let error = viewModel.downloadError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppCardBackground())
                }

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.searchResults) { result in
                            Button {
                                Task { await viewModel.queueDownload(result: result) }
                            } label: {
                                SearchResultRow(result: result)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isQueueing)
                        }
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 16) {
                    if let indexer = result.indexer {
                        label(icon: "building.2", text: indexer)
                    }
                    label(icon: "doc", text: result.formattedSize)
                    if let seeders = result.seeders {
                        label(icon: "arrow.up", text: "\(seeders)")
                    }
                    if let leechers = result.leechers {
                        label(icon: "arrow.down", text: "\(leechers)")
                    }
                }
            }

            Spacer(minLength: 12)

            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(Color.white.opacity(0.50))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(isFocused ? Color.black.opacity(0.60) : Color.white.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(isFocused ? 0.20 : 0.10), lineWidth: 1)
                }
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private func label(icon: String, text: String) -> some View {
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
