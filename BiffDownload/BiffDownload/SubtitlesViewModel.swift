//
//  SubtitlesViewModel.swift
//  BiffDownload
//

import Combine
import Foundation
import os

@MainActor
final class SubtitlesViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var appendEpisode = false
    @Published var seasonNumber = 1
    @Published var episodeNumber = 1
    @Published var language = "en"

    @Published private(set) var root: String?
    @Published private(set) var currentPath = ""
    @Published private(set) var absolutePath: String?
    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var selectedVideo: FileEntry?
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoadingFiles = false
    @Published private(set) var isDownloadingSubtitle = false
    @Published private(set) var isMergingSubtitle = false
    @Published private(set) var downloadedSubtitlePath: String?
    @Published private(set) var outputVideoPath: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private var apiService: APIService?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BiffDownload",
        category: "Subtitles"
    )

    var isConfigured: Bool {
        apiService != nil
    }

    var canGoUp: Bool {
        !currentPath.isEmpty
    }

    var pathDisplayName: String {
        currentPath.isEmpty ? "Download Root" : currentPath
    }

    var episodeTag: String {
        let s = String(format: "%02d", seasonNumber)
        let e = String(format: "%02d", episodeNumber)
        return "s\(s)e\(e)"
    }

    var fullSearchName: String {
        var name = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if appendEpisode {
            name += name.isEmpty ? episodeTag : " \(episodeTag)"
        }
        return name
    }

    var visibleEntries: [FileEntry] {
        entries.filter { $0.isDirectory || Self.isVideoFile($0.name) }
    }

    var isWorking: Bool {
        isDownloadingSubtitle || isMergingSubtitle
    }

    var primaryActionTitle: String {
        if isDownloadingSubtitle {
            return "Finding..."
        }
        if isMergingSubtitle {
            return "Applying..."
        }
        return "Find and Apply"
    }

    func configure(baseURL: URL) {
        if apiService?.baseURL == baseURL {
            return
        }

        apiService = APIService(baseURL: baseURL)
        root = nil
        currentPath = ""
        absolutePath = nil
        entries = []
        selectedVideo = nil
        hasLoaded = false
        clearResultState()
        logger.info("Configured subtitles API baseURL=\(baseURL.absoluteString, privacy: .public)")
    }

    func loadRoot() async {
        await load(path: "")
    }

    func refresh() async {
        await load(path: currentPath)
    }

    func goUp() async {
        guard canGoUp else { return }
        await load(path: parentPath(of: currentPath))
    }

    func openFolder(_ entry: FileEntry) async {
        guard entry.isDirectory else { return }
        await load(path: entry.relativePath)
    }

    func selectVideo(_ entry: FileEntry) {
        guard !entry.isDirectory, Self.isVideoFile(entry.name) else { return }
        selectedVideo = entry
        clearResultState()
        logger.info("Selected subtitle video path=\(entry.relativePath, privacy: .public)")
    }

    func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    func applySubtitle() async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            logger.error("Subtitle apply requested without an API service.")
            return
        }

        let name = fullSearchName
        guard !name.isEmpty else {
            errorMessage = "Enter a show name or search term."
            logger.error("Subtitle apply requested with an empty search name.")
            return
        }

        guard let selectedVideo else {
            errorMessage = "Choose the video file to apply subtitles to."
            logger.error("Subtitle apply requested without a selected video.")
            return
        }

        let trimmedLanguage = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let resolvedLanguage = trimmedLanguage.isEmpty ? "en" : trimmedLanguage

        clearResultState()
        isDownloadingSubtitle = true
        statusMessage = "Finding subtitle..."
        logger.info(
            "Downloading subtitle videoPath=\(selectedVideo.relativePath, privacy: .public) name=\(name, privacy: .public) language=\(resolvedLanguage, privacy: .public)"
        )

        do {
            let downloadResponse = try await apiService.downloadSubtitle(
                path: selectedVideo.relativePath,
                name: name,
                language: resolvedLanguage
            )
            isDownloadingSubtitle = false

            guard let subtitlePath = downloadResponse.subtitlePath, !subtitlePath.isEmpty else {
                statusMessage = downloadResponse.message ?? "No subtitle found."
                logger.info(
                    "No subtitle found videoPath=\(selectedVideo.relativePath, privacy: .public) message=\(downloadResponse.message ?? "<none>", privacy: .public)"
                )
                return
            }

            downloadedSubtitlePath = subtitlePath
            isMergingSubtitle = true
            statusMessage = "Subtitle found. Applying to video..."
            logger.info(
                "Merging subtitle videoPath=\(selectedVideo.relativePath, privacy: .public) subtitlePath=\(subtitlePath, privacy: .public)"
            )

            let mergeResponse = try await apiService.mergeSubtitle(
                videoPath: selectedVideo.relativePath,
                subtitlePath: subtitlePath
            )
            isMergingSubtitle = false
            outputVideoPath = mergeResponse.outputPath
            statusMessage = mergeResponse.message ?? "Subtitle applied."
            logger.info(
                "Subtitle merge completed outputPath=\(mergeResponse.outputPath ?? "<unknown>", privacy: .public) message=\(mergeResponse.message ?? "<none>", privacy: .public)"
            )
            await refreshAfterApplying(to: mergeResponse.outputPath)
        } catch {
            isDownloadingSubtitle = false
            isMergingSubtitle = false
            errorMessage = error.localizedDescription
            statusMessage = nil
            logger.error(
                "Subtitle apply failed videoPath=\(selectedVideo.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func clearResultState() {
        errorMessage = nil
        statusMessage = nil
        downloadedSubtitlePath = nil
        outputVideoPath = nil
    }

    private func load(path: String) async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            logger.error("Subtitle file load requested without an API service.")
            return
        }

        isLoadingFiles = true
        errorMessage = nil
        logger.info("Loading subtitle file choices path=\(path, privacy: .public)")

        defer {
            isLoadingFiles = false
        }

        do {
            let response = try await apiService.files(path: path)
            root = response.root
            currentPath = response.path ?? path
            absolutePath = response.absolutePath
            entries = response.entries ?? []
            hasLoaded = true
            selectedVideo = selectedVideo.flatMap { selected in
                entries.first(where: { isSamePath($0.relativePath, selected.relativePath) })
            }
            logger.info(
                "Loaded subtitle file choices path=\(self.currentPath, privacy: .public) count=\(self.entries.count)"
            )
        } catch {
            errorMessage = error.localizedDescription
            logger.error(
                "Subtitle file load failed path=\(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func refreshAfterApplying(to outputPath: String?) async {
        let outputParent = parentPath(of: outputPath ?? selectedVideo?.relativePath ?? "")
        if isSamePath(outputParent, currentPath) {
            await load(path: currentPath)
        }
    }

    private func parentPath(of path: String) -> String {
        let parts = pathComponents(path)
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "\\")
    }

    private func pathComponents(_ path: String) -> [String] {
        path.split { character in
            character == "\\" || character == "/"
        }
        .map(String.init)
    }

    private func normalizedPath(_ path: String) -> String {
        pathComponents(path).joined(separator: "\\").lowercased()
    }

    private func isSamePath(_ lhs: String, _ rhs: String) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    private static func isVideoFile(_ name: String) -> Bool {
        let videoExtensions: Set<String> = [
            "mkv", "mp4", "m4v", "mov", "avi", "wmv", "webm", "ts", "m2ts"
        ]
        let ext = (name as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }
}
