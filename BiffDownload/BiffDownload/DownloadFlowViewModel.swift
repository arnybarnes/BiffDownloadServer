//
//  DownloadFlowViewModel.swift
//  BiffDownload
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class DownloadFlowViewModel: ObservableObject {

    // MARK: - Flow state

    enum FlowStep {
        case search
        case results
        case downloading
    }

    @Published var flowStep: FlowStep = .search

    // MARK: - Search

    @Published var searchText = ""
    @Published var appendSuffix = true
    @Published var appendEpisode = false
    @Published var seasonNumber = 1
    @Published var episodeNumber = 1
    private let suffix = " 1080p x265"
    @Published private(set) var isSearching = false
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var searchMessage: String?
    @Published private(set) var searchError: String?

    // MARK: - Download

    @Published private(set) var isQueueing = false
    @Published private(set) var selectedResult: SearchResult?
    @Published private(set) var downloadGid: String?
    @Published private(set) var downloadInfo: DownloadInfo?
    @Published private(set) var downloadError: String?
    @Published private(set) var isPolling = false

    private var apiService: APIService?
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 2

    // MARK: - Setup

    func configure(baseURL: URL, pollingInterval: TimeInterval = 2) {
        self.apiService = APIService(baseURL: baseURL)
        self.pollingInterval = pollingInterval
    }

    var isConfigured: Bool { apiService != nil }

    var episodeTag: String {
        let s = String(format: "%02d", seasonNumber)
        let e = String(format: "%02d", episodeNumber)
        return "s\(s)e\(e)"
    }

    var fullQuery: String {
        var query = searchText
        if appendEpisode {
            query += " \(episodeTag)"
        }
        if appendSuffix {
            query += suffix
        }
        return query
    }

    // MARK: - Search

    func performSearch() async {
        guard let apiService else {
            searchError = "Not connected to server."
            return
        }

        let query = fullQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchError = "Enter a search term."
            return
        }

        isSearching = true
        searchError = nil
        searchMessage = nil
        searchResults = []

        do {
            let response = try await apiService.search(query: query)
            searchResults = response.items ?? []
            searchMessage = response.message
            if searchResults.isEmpty {
                searchError = "No results found for \"\(query)\"."
            }
            flowStep = .results
        } catch {
            searchError = error.localizedDescription
        }

        isSearching = false
    }

    // MARK: - Queue Download

    func queueDownload(result: SearchResult) async {
        guard let apiService else {
            downloadError = "Not connected to server."
            return
        }

        selectedResult = result
        isQueueing = true
        downloadError = nil
        downloadInfo = nil
        downloadGid = nil

        do {
            let response = try await apiService.queueDownload(resultId: result.resultId)
            guard let gid = response.gid else {
                downloadError = "Server did not return a download ID."
                isQueueing = false
                return
            }
            downloadGid = gid
            flowStep = .downloading
            isQueueing = false
            startPolling(gid: gid)
        } catch {
            downloadError = error.localizedDescription
            isQueueing = false
        }
    }

    // MARK: - Polling

    private func startPolling(gid: String) {
        stopPolling()
        isPolling = true

        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.pollOnce(gid: gid)

                if let info = self.downloadInfo, (info.isComplete || info.isError) {
                    self.isPolling = false
                    return
                }

                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
            }

            self.isPolling = false
        }
    }

    private func pollOnce(gid: String) async {
        guard let apiService else { return }

        do {
            let response = try await apiService.downloadStatus(gid: gid)
            downloadInfo = response.download
            downloadError = nil
        } catch {
            downloadError = error.localizedDescription
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    // MARK: - Navigation

    func cancelAndReset() {
        stopPolling()
        selectedResult = nil
        downloadGid = nil
        downloadInfo = nil
        downloadError = nil
        isQueueing = false
        flowStep = .search
    }

    func backToResults() {
        stopPolling()
        downloadGid = nil
        downloadInfo = nil
        downloadError = nil
        isQueueing = false
        flowStep = .results
    }

    func newSearch() {
        stopPolling()
        searchText = ""
        searchResults = []
        searchMessage = nil
        searchError = nil
        selectedResult = nil
        downloadGid = nil
        downloadInfo = nil
        downloadError = nil
        isQueueing = false
        flowStep = .search
    }
}
