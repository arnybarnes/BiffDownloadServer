//
//  DownloadFlowViewModel.swift
//  BiffDownload
//

import Combine
import Foundation
import os
import SwiftUI

@MainActor
final class DownloadFlowViewModel: ObservableObject {

    // MARK: - Flow state

    enum FlowStep {
        case search
        case results
        case destination
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
    @Published private(set) var isLoadingFolders = false
    @Published private(set) var downloadFolders: [DownloadFolderChoice] = [DownloadFolderChoice.fallback()]
    @Published var selectedFolderKey = ""
    @Published private(set) var folderLoadError: String?

    // MARK: - Download

    @Published private(set) var isQueueing = false
    @Published private(set) var selectedResult: SearchResult?
    @Published private(set) var downloadGid: String?
    @Published private(set) var downloadInfo: DownloadInfo?
    @Published private(set) var downloadError: String?
    @Published private(set) var isPolling = false
    @Published private(set) var isDeletingTempFiles = false
    @Published private(set) var queuedDirectory: String?
    @Published private(set) var queuedStagingDirectory: String?
    @Published private(set) var queuedFileName: String?

    private var apiService: APIService?
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 2
    private var hasRequestedFinalization = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BiffDownload",
        category: "DownloadFlow"
    )

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

    var selectedDownloadFolder: DownloadFolderChoice? {
        if let selection = downloadFolders.first(where: { $0.key == selectedFolderKey }) {
            return selection
        }

        return downloadFolders.first(where: { $0.isDefault }) ?? downloadFolders.first
    }

    var episodeRenameSummary: String? {
        guard appendEpisode else { return nil }
        return "Will request file name: \(episodeTag). Server decides the extension."
    }

    // MARK: - Search

    func performSearch() async {
        guard let apiService else {
            searchError = "Not connected to server."
            logger.error("Search requested without an API service.")
            return
        }

        let query = fullQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchError = "Enter a search term."
            logger.error("Search requested with an empty query.")
            return
        }

        logger.info("Starting search query=\(query, privacy: .public)")

        isSearching = true
        isLoadingFolders = true
        searchError = nil
        searchMessage = nil
        searchResults = []
        folderLoadError = nil

        defer {
            isSearching = false
            isLoadingFolders = false
        }

        do {
            async let folderResponse = apiService.downloadFolders()
            let response = try await apiService.search(query: query)
            searchResults = response.items ?? []
            searchMessage = response.message
            logger.info(
                "Search completed query=\(query, privacy: .public) resultCount=\(self.searchResults.count)"
            )

            do {
                let folders = try await folderResponse
                applyDownloadFolders(folders)
                logger.info(
                    "Loaded destination folders count=\(self.downloadFolders.count) selectedKey=\(self.selectedFolderKey, privacy: .public)"
                )
            } catch {
                downloadFolders = [DownloadFolderChoice.fallback()]
                selectedFolderKey = ""
                folderLoadError = "Could not load destination folders. Downloads will use the default folder."
                logger.error("Destination folder load failed: \(error.localizedDescription, privacy: .public)")
            }

            if searchResults.isEmpty {
                searchError = "No results found for \"\(query)\"."
                logger.info("Search returned no results for query=\(query, privacy: .public)")
            }
            flowStep = .results
        } catch {
            searchError = error.localizedDescription
            logger.error("Search failed for query=\(query, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Queue Download

    func selectResultForDownload(_ result: SearchResult) {
        selectedResult = result
        downloadError = nil
        downloadGid = nil
        downloadInfo = nil
        queuedDirectory = nil
        queuedStagingDirectory = nil
        queuedFileName = nil
        isDeletingTempFiles = false
        hasRequestedFinalization = false
        flowStep = .destination
        logger.info(
            "Selected result for download resultId=\(result.resultId, privacy: .public) title=\(result.title, privacy: .public)"
        )
    }

    func selectDownloadFolder(_ folder: DownloadFolderChoice) {
        selectedFolderKey = folder.key
        logger.info(
            "Selected destination folder key=\(folder.key, privacy: .public) path=\(folder.absolutePath ?? "<default>", privacy: .public)"
        )
    }

    func queueSelectedResult() async {
        guard let selectedResult else {
            downloadError = "Select a result before starting a download."
            logger.error("Queue requested without a selected result.")
            return
        }

        await queueDownload(result: selectedResult)
    }

    private func queueDownload(result: SearchResult) async {
        guard let apiService else {
            downloadError = "Not connected to server."
            logger.error("Queue requested without an API service.")
            return
        }

        selectedResult = result
        isQueueing = true
        downloadError = nil
        downloadInfo = nil
        downloadGid = nil
        queuedDirectory = nil
        queuedStagingDirectory = nil
        queuedFileName = nil
        isDeletingTempFiles = false
        hasRequestedFinalization = false

        let folder = selectedDownloadFolder
        let requestedFileName = requestedFileName()
        logger.info(
            "Queueing download resultId=\(result.resultId, privacy: .public) folderKey=\(folder?.key ?? "<default>", privacy: .public) folderPath=\(folder?.absolutePath ?? "<default>", privacy: .public) requestedFileName=\(requestedFileName ?? "<none>", privacy: .public)"
        )

        do {
            let response = try await apiService.queueDownload(
                resultId: result.resultId,
                folder: folder?.key,
                fileName: requestedFileName
            )
            guard let gid = response.gid else {
                downloadError = "Server did not return a download ID."
                isQueueing = false
                logger.error("Queue response missing gid for resultId=\(result.resultId, privacy: .public)")
                return
            }
            queuedDirectory = response.directory ?? folder?.absolutePath
            queuedStagingDirectory = response.stagingDirectory
            queuedFileName = response.fileName ?? requestedFileName
            downloadGid = gid
            flowStep = .downloading
            isQueueing = false
            logger.info(
                "Download queued gid=\(gid, privacy: .public) queuedDirectory=\(self.queuedDirectory ?? "<none>", privacy: .public) stagingDirectory=\(self.queuedStagingDirectory ?? "<none>", privacy: .public) queuedFileName=\(self.queuedFileName ?? "<none>", privacy: .public)"
            )
            startPolling(gid: gid)
        } catch {
            downloadError = error.localizedDescription
            isQueueing = false
            logger.error(
                "Queue failed resultId=\(result.resultId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Polling

    private func startPolling(gid: String) {
        stopPolling()
        isPolling = true
        logger.info("Starting download polling gid=\(gid, privacy: .public) intervalSeconds=\(self.pollingInterval)")

        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.pollOnce(gid: gid)

                if let info = self.downloadInfo, info.isTerminalForUI {
                    self.isPolling = false
                    self.logger.info(
                        "Stopping polling gid=\(gid, privacy: .public) terminalState=\(info.state ?? "<unknown>", privacy: .public) finalizationState=\(info.finalizationState, privacy: .public)"
                    )
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
            if let info = response.download {
                syncFinalizationRequestState(from: info)
                logger.debug(
                    "Poll gid=\(gid, privacy: .public) state=\(info.state ?? "<unknown>", privacy: .public) completed=\(info.completedBytes ?? 0)/\(info.totalBytes ?? 0) speed=\(info.downloadSpeedBytesPerSecond ?? 0) directory=\(info.displayDirectory ?? "<none>", privacy: .public) primaryPath=\(info.displayPrimaryPath ?? "<none>", privacy: .public) finalizationState=\(info.finalizationState, privacy: .public)"
                )

                if shouldRequestFinalization(for: info) {
                    logger.info(
                        "Download bytes complete; requesting finalization gid=\(gid, privacy: .public) state=\(info.state ?? "<unknown>", privacy: .public)"
                    )
                    await requestFinalization(gid: gid)
                    return
                }

                if info.isTerminalForUI {
                    logger.info(
                        "Poll reached terminal UI state gid=\(gid, privacy: .public) state=\(info.state ?? "<unknown>", privacy: .public) finalizationState=\(info.finalizationState, privacy: .public); stopping polling."
                    )
                    stopPolling()
                }
            } else {
                logger.error("Poll response missing download payload gid=\(gid, privacy: .public)")
            }
        } catch {
            downloadError = error.localizedDescription
            logger.error("Poll failed gid=\(gid, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        logger.debug("Stopped polling.")
    }

    // MARK: - Navigation

    func cancelAndReset() {
        stopPolling()
        selectedResult = nil
        downloadGid = nil
        downloadInfo = nil
        downloadError = nil
        queuedDirectory = nil
        queuedStagingDirectory = nil
        queuedFileName = nil
        isQueueing = false
        isDeletingTempFiles = false
        hasRequestedFinalization = false
        flowStep = .search
        logger.info("Cancelled download flow and reset to search.")
    }

    func backToResults() {
        stopPolling()
        selectedResult = nil
        downloadGid = nil
        downloadInfo = nil
        downloadError = nil
        queuedDirectory = nil
        queuedStagingDirectory = nil
        queuedFileName = nil
        isQueueing = false
        isDeletingTempFiles = false
        hasRequestedFinalization = false
        flowStep = .results
        logger.info("Returned to search results.")
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
        folderLoadError = nil
        queuedDirectory = nil
        queuedStagingDirectory = nil
        queuedFileName = nil
        isQueueing = false
        isDeletingTempFiles = false
        hasRequestedFinalization = false
        flowStep = .search
        logger.info("Started a new search flow.")
    }

    func deleteTempFiles() async {
        guard let apiService else {
            downloadError = "Not connected to server."
            logger.error("Temp cleanup requested without an API service.")
            return
        }

        guard let gid = downloadGid else {
            downloadError = "No download is available for temp cleanup."
            logger.error("Temp cleanup requested without a gid.")
            return
        }

        guard downloadInfo?.isFinalizationCompleted == true else {
            downloadError = "Copy the selected video before deleting temp files."
            logger.error("Temp cleanup requested before finalization completed gid=\(gid, privacy: .public)")
            return
        }

        isDeletingTempFiles = true
        downloadError = nil
        logger.info("Requesting temp cleanup gid=\(gid, privacy: .public)")

        defer {
            isDeletingTempFiles = false
        }

        do {
            let response = try await apiService.deleteTempFiles(gid: gid)
            downloadInfo = response.download
            downloadError = nil
            logger.info(
                "Temp cleanup completed gid=\(gid, privacy: .public) message=\(response.message ?? "<none>", privacy: .public) state=\(response.download?.cleanupState ?? "<none>", privacy: .public)"
            )
        } catch {
            downloadError = error.localizedDescription
            logger.error(
                "Temp cleanup failed gid=\(gid, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func requestedFileName() -> String? {
        guard appendEpisode else { return nil }
        return episodeTag
    }

    private func applyDownloadFolders(_ response: DownloadFoldersResponse) {
        let resolvedFolders = response.folders?.isEmpty == false
            ? response.folders ?? []
            : [DownloadFolderChoice.fallback(root: response.root)]

        downloadFolders = resolvedFolders

        if !resolvedFolders.contains(where: { $0.key == selectedFolderKey }) {
            selectedFolderKey = resolvedFolders.first(where: { $0.isDefault })?.key
                ?? resolvedFolders.first?.key
                ?? ""
        }
    }

    private func syncFinalizationRequestState(from info: DownloadInfo) {
        switch info.finalizationState {
        case "queued", "in_progress", "completed", "error":
            hasRequestedFinalization = true
        default:
            hasRequestedFinalization = false
        }
    }

    private func shouldRequestFinalization(for info: DownloadInfo) -> Bool {
        info.isReadyForFinalization
            && !info.isFinalizationInProgress
            && !info.isFinalizationCompleted
            && !info.isFinalizationError
            && !hasRequestedFinalization
    }

    private func requestFinalization(gid: String) async {
        guard let apiService else { return }

        hasRequestedFinalization = true
        do {
            let response = try await apiService.finalizeDownload(gid: gid)
            downloadInfo = response.download
            downloadError = nil
            if let info = response.download {
                syncFinalizationRequestState(from: info)
                logger.info(
                    "Finalization requested gid=\(gid, privacy: .public) state=\(info.finalizationState, privacy: .public) message=\(response.message ?? "<none>", privacy: .public)"
                )
            } else {
                logger.info(
                    "Finalization requested gid=\(gid, privacy: .public) message=\(response.message ?? "<none>", privacy: .public)"
                )
            }
        } catch {
            hasRequestedFinalization = false
            downloadError = error.localizedDescription
            logger.error(
                "Finalization request failed gid=\(gid, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
