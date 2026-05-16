//
//  AIViewModel.swift
//  BiffDownload
//

import Combine
import Foundation
import os

struct AIJobStageDisplay: Identifiable {
    enum State {
        case pending
        case active
        case completed
        case failed
    }

    let id: String
    let label: String
    let state: State
}

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
    @Published private(set) var generateJob: SubtitleGenerateJob?
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
    private var generateJobPollingTask: Task<Void, Never>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BiffDownload",
        category: "AI"
    )
    private static let generateStageDefinitions: [(id: String, label: String)] = [
        ("extracting_audio", "Extracting audio"),
        ("uploading_audio", "Uploading audio"),
        ("transcribing", "Generating subtitles"),
        ("receiving_srt", "Receiving subtitle file"),
        ("muxing", "Merging video"),
    ]

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
        if isGeneratingSubtitles {
            return generateJob?.stageLabel ?? "Generating..."
        }
        return "Generate and Apply"
    }

    var hasGenerateJob: Bool {
        generateJob != nil
    }

    var generateJobStageLabel: String {
        generateJob?.stageLabel ?? "Queued"
    }

    var generateJobDetail: String {
        generateJob?.detail ?? "Preparing subtitle generation."
    }

    var generateJobProgressFraction: Double {
        generateJob?.progressFraction ?? 0
    }

    var generateJobActiveStage: String? {
        generateJob?.activeStage ?? generateJob?.state
    }

    var generateJobProgressPercentText: String? {
        guard let generateJob else {
            return nil
        }
        if generateJob.state == "transcribing" && generateJob.stageProgressPercent == nil {
            return nil
        }
        return "\(generateJob.progressPercent ?? 0)%"
    }

    var generateJobStageProgressText: String? {
        guard let stageProgressPercent = generateJob?.stageProgressPercent else {
            return nil
        }
        return "Stage \(stageProgressPercent)%"
    }

    var generateJobElapsedText: String? {
        guard let elapsedSeconds = generateJob?.elapsedSeconds else {
            return nil
        }
        let elapsed = formatElapsedText(elapsedSeconds)
        if generateJob?.state == "transcribing" {
            return "AI elapsed \(elapsed)"
        }
        return "\(elapsed) elapsed"
    }

    var generateJobStages: [AIJobStageDisplay] {
        let currentStage = generateJobActiveStage
        let currentStageIndex = Self.generateStageDefinitions.firstIndex { $0.id == currentStage }

        return Self.generateStageDefinitions.enumerated().map { index, stage in
            let state: AIJobStageDisplay.State

            switch generateJob?.state {
            case "completed":
                state = .completed
            case "failed":
                if let currentStageIndex, index < currentStageIndex {
                    state = .completed
                } else if let currentStageIndex, index == currentStageIndex {
                    state = .failed
                } else {
                    state = .pending
                }
            default:
                if let currentStageIndex, index < currentStageIndex {
                    state = .completed
                } else if let currentStageIndex, index == currentStageIndex {
                    state = .active
                } else {
                    state = .pending
                }
            }

            return AIJobStageDisplay(id: stage.id, label: stage.label, state: state)
        }
    }

    deinit {
        generateJobPollingTask?.cancel()
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
        cancelGenerateJobPolling()
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
        statusMessage = nil
        logger.info(
            "Generating subtitles videoPath=\(selectedVideo.relativePath, privacy: .public) language=<auto>"
        )

        do {
            let response = try await apiService.startGenerateSubtitleJob(videoPath: selectedVideo.relativePath)
            guard let job = response.job else {
                isGeneratingSubtitles = false
                errorMessage = "The server did not return a subtitle generation job."
                logger.error("Subtitle generation job creation returned no job payload.")
                return
            }
            applyGenerateJob(job)
            startPollingGenerateJob(jobID: job.id)
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
        cancelGenerateJobPolling()
        generateJob = nil
        errorMessage = nil
        statusMessage = nil
        generatedSubtitlePath = nil
        outputVideoPath = nil
        detectedLanguage = nil
        segmentCount = nil
        transcriptionModel = nil
    }

    private func cancelGenerateJobPolling() {
        generateJobPollingTask?.cancel()
        generateJobPollingTask = nil
    }

    private func startPollingGenerateJob(jobID: String) {
        cancelGenerateJobPolling()
        generateJobPollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 750_000_000)
                } catch {
                    return
                }

                let shouldContinue = await self.pollGenerateJob(jobID: jobID)
                if !shouldContinue {
                    return
                }
            }
        }
    }

    private func pollGenerateJob(jobID: String) async -> Bool {
        guard let apiService else {
            isGeneratingSubtitles = false
            errorMessage = "Not connected to server."
            return false
        }

        do {
            let response = try await apiService.generateSubtitleJob(id: jobID)
            guard let job = response.job else {
                isGeneratingSubtitles = false
                errorMessage = "The server returned an empty subtitle generation job payload."
                return false
            }

            applyGenerateJob(job)

            if job.isTerminal {
                isGeneratingSubtitles = false
                generateJobPollingTask = nil

                if job.state == "completed" {
                    statusMessage = job.message ?? "Generated subtitles and muxed a copy."
                    errorMessage = nil
                    await refreshAfterGenerating(to: job.outputPath)
                } else {
                    errorMessage = job.error ?? job.detail ?? "Subtitle generation failed."
                    statusMessage = nil
                }

                await refreshMacServiceStatus()
                return false
            }

            return true
        } catch {
            isGeneratingSubtitles = false
            errorMessage = error.localizedDescription
            statusMessage = nil
            logger.error("Subtitle generation job polling failed jobID=\(jobID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func applyGenerateJob(_ job: SubtitleGenerateJob) {
        generateJob = job
        generatedSubtitlePath = job.subtitlePath
        outputVideoPath = job.outputPath
        detectedLanguage = job.transcription?.detectedLanguage
        segmentCount = job.transcription?.segmentCount
        transcriptionModel = job.transcription?.model

        if let responseService = job.macService {
            macServiceStatus = merge(macServiceStatus, with: responseService)
        }
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

    private func formatElapsedText(_ elapsedSeconds: Double) -> String {
        let rounded = max(0, Int(elapsedSeconds.rounded()))
        let minutes = rounded / 60
        let seconds = rounded % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func isVideoFile(_ name: String) -> Bool {
        let videoExtensions: Set<String> = [
            "mkv", "mp4", "m4v", "mov", "avi", "wmv", "webm", "ts", "m2ts"
        ]
        let ext = (name as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }
}
