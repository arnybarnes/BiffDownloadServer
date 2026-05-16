//
//  AIViewModel.swift
//  BiffDownload
//

import Combine
import Foundation
import os

@MainActor
final class AIViewModel: ObservableObject {
    @Published private(set) var root: String?
    @Published private(set) var currentPath = ""
    @Published private(set) var absolutePath: String?
    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var selectedVideo: FileEntry?
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoadingFiles = false
    @Published private(set) var isRefreshingService = false
    @Published private(set) var isGeneratingSubtitles = false
    @Published private(set) var generatedSubtitlePath: String?
    @Published private(set) var outputVideoPath: String?
    @Published private(set) var detectedLanguage: String?
    @Published private(set) var segmentCount: Int?
    @Published private(set) var transcriptionModel: String?
    @Published private(set) var macServiceStatus: MacServiceStatus?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var serviceErrorMessage: String?

    private var apiService: APIService?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BiffDownload",
        category: "AI"
    )

    var canGoUp: Bool {
        !currentPath.isEmpty
    }

    var pathDisplayName: String {
        currentPath.isEmpty ? "Download Root" : currentPath
    }

    var visibleEntries: [FileEntry] {
        entries.filter { $0.isDirectory || Self.isVideoFile($0.name) }
    }

    var isWorking: Bool {
        isGeneratingSubtitles
    }

    var primaryActionTitle: String {
        isGeneratingSubtitles ? "Generating..." : "Generate and Apply"
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
        macServiceStatus = nil
        serviceErrorMessage = nil
        clearResultState()
        logger.info("Configured AI API baseURL=\(baseURL.absoluteString, privacy: .public)")
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
        logger.info("Selected AI video path=\(entry.relativePath, privacy: .public)")
    }

    func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    func refreshMacServiceStatus() async {
        guard let apiService else {
            serviceErrorMessage = "Not connected to server."
            logger.error("Mac service status requested without an API service.")
            return
        }

        isRefreshingService = true
        serviceErrorMessage = nil

        defer {
            isRefreshingService = false
        }

        do {
            let response = try await apiService.macServiceStatus()
            macServiceStatus = response.service
            logger.info(
                "Loaded Mac service status registered=\(response.service?.registered == true, privacy: .public) online=\(response.service?.online == true, privacy: .public)"
            )
        } catch {
            macServiceStatus = nil
            serviceErrorMessage = error.localizedDescription
            logger.error("Mac service status request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func generateSubtitles() async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            logger.error("Generate subtitles requested without an API service.")
            return
        }

        guard let selectedVideo else {
            errorMessage = "Choose the video file to generate subtitles for."
            logger.error("Generate subtitles requested without a selected video.")
            return
        }

        clearResultState()
        isGeneratingSubtitles = true
        statusMessage = "Generating subtitles on the Mac service with automatic language detection..."
        logger.info(
            "Generating subtitles videoPath=\(selectedVideo.relativePath, privacy: .public) language=<auto>"
        )

        do {
            let response = try await apiService.generateSubtitle(videoPath: selectedVideo.relativePath)
            isGeneratingSubtitles = false

            generatedSubtitlePath = response.subtitlePath
            outputVideoPath = response.outputPath
            detectedLanguage = response.transcription?.detectedLanguage
            segmentCount = response.transcription?.segmentCount
            transcriptionModel = response.transcription?.model
            statusMessage = response.message ?? "Generated subtitles and muxed a copy."

            if let responseService = response.macService {
                macServiceStatus = merge(macServiceStatus, with: responseService)
            }

            logger.info(
                "Generate subtitles completed subtitlePath=\(response.subtitlePath ?? "<none>", privacy: .public) outputPath=\(response.outputPath ?? "<none>", privacy: .public)"
            )

            await refreshAfterGenerating(to: response.outputPath)
            await refreshMacServiceStatus()
        } catch {
            isGeneratingSubtitles = false
            errorMessage = error.localizedDescription
            statusMessage = nil
            logger.error(
                "Generate subtitles failed videoPath=\(selectedVideo.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            await refreshMacServiceStatus()
        }
    }

    private func clearResultState() {
        errorMessage = nil
        statusMessage = nil
        generatedSubtitlePath = nil
        outputVideoPath = nil
        detectedLanguage = nil
        segmentCount = nil
        transcriptionModel = nil
    }

    private func load(path: String) async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            logger.error("AI file load requested without an API service.")
            return
        }

        isLoadingFiles = true
        errorMessage = nil
        logger.info("Loading AI file choices path=\(path, privacy: .public)")

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
                "Loaded AI file choices path=\(self.currentPath, privacy: .public) count=\(self.entries.count)"
            )
        } catch {
            errorMessage = error.localizedDescription
            logger.error(
                "AI file load failed path=\(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func refreshAfterGenerating(to outputPath: String?) async {
        let outputParent = parentPath(of: outputPath ?? selectedVideo?.relativePath ?? "")
        if isSamePath(outputParent, currentPath) {
            await load(path: currentPath)
        }
    }

    private func merge(
        _ current: MacServiceStatus?,
        with responseService: GeneratedSubtitleMacService
    ) -> MacServiceStatus {
        MacServiceStatus(
            name: current?.name ?? "mac-api",
            registered: current?.registered ?? true,
            online: current?.online ?? true,
            heartbeatFresh: current?.heartbeatFresh ?? true,
            lastSeen: current?.lastSeen,
            lastSeenAgeSeconds: current?.lastSeenAgeSeconds,
            staleAfterSeconds: current?.staleAfterSeconds,
            hostname: responseService.hostname ?? current?.hostname,
            instanceId: current?.instanceId,
            version: responseService.version ?? current?.version,
            baseUrl: responseService.baseUrl ?? current?.baseUrl,
            healthUrl: responseService.healthUrl ?? current?.healthUrl,
            port: current?.port,
            addresses: current?.addresses,
            healthReachable: current?.healthReachable,
            health: current?.health,
            healthError: current?.healthError
        )
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
