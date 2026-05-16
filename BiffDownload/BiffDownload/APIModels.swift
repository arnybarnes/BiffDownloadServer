//
//  APIModels.swift
//  BiffDownload
//

import Foundation

// MARK: - Search

struct SearchResponse: Decodable {
    let status: String
    let query: String?
    let message: String?
    let provider: String?
    let count: Int?
    let items: [SearchResult]?
}

struct SearchResult: Decodable, Identifiable {
    let resultId: String
    let title: String
    let indexer: String?
    let sizeBytes: Int64?
    let seeders: Int?
    let leechers: Int?
    let publishedAt: String?
    let protocol_: String?
    let hasSource: Bool?

    var id: String { resultId }

    var formattedSize: String {
        guard let sizeBytes, sizeBytes > 0 else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    enum CodingKeys: String, CodingKey {
        case resultId, title, indexer, sizeBytes, seeders, leechers, publishedAt, hasSource
        case protocol_ = "protocol"
    }
}

// MARK: - Download Folders

struct DownloadFoldersResponse: Decodable {
    let status: String
    let root: String?
    let count: Int?
    let folders: [DownloadFolderChoice]?
}

struct DownloadFolderChoice: Decodable, Identifiable, Hashable {
    let key: String
    let name: String
    let relativePath: String?
    let absolutePath: String?
    let isDefault: Bool

    var id: String {
        key.isEmpty ? "__default__" : key
    }

    var displayName: String {
        name.isEmpty ? "Default" : name
    }

    var subtitle: String {
        if let absolutePath, !absolutePath.isEmpty {
            return absolutePath
        }
        return "Default download root"
    }

    static func fallback(root: String? = nil) -> DownloadFolderChoice {
        DownloadFolderChoice(
            key: "",
            name: "Default",
            relativePath: "",
            absolutePath: root,
            isDefault: true
        )
    }
}

// MARK: - Disk

struct DiskResponse: Decodable {
    let status: String
    let disk: DiskInfo?
}

struct DiskInfo: Decodable {
    let path: String
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
    let percentUsed: Double?

    var usedFraction: Double {
        if let percentUsed {
            return min(max(percentUsed / 100, 0), 1)
        }

        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var formattedTotal: String {
        Self.byteFormatter.string(fromByteCount: totalBytes)
    }

    var formattedUsed: String {
        Self.byteFormatter.string(fromByteCount: usedBytes)
    }

    var formattedFree: String {
        Self.byteFormatter.string(fromByteCount: freeBytes)
    }

    var formattedPercentUsed: String {
        let percent = percentUsed ?? (usedFraction * 100)
        return "\(Self.percentFormatter.string(from: NSNumber(value: percent)) ?? "0")%"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

// MARK: - Files

struct FileListResponse: Decodable {
    let status: String
    let root: String?
    let path: String?
    let absolutePath: String?
    let count: Int?
    let entries: [FileEntry]?
}

struct FileEntry: Decodable, Identifiable, Hashable {
    let name: String
    let relativePath: String
    let isDirectory: Bool
    let sizeBytes: Int64?
    let modifiedAt: String?

    var id: String { relativePath }

    var formattedSize: String {
        guard !isDirectory, let sizeBytes, sizeBytes >= 0 else {
            return isDirectory ? "Folder" : "Unknown"
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    var formattedModifiedAt: String {
        guard let modifiedAt, !modifiedAt.isEmpty else { return "Modified date unknown" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let date = formatter.date(from: modifiedAt) ?? {
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            return fallbackFormatter.date(from: modifiedAt)
        }()

        guard let date else { return modifiedAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct FileDeleteResponse: Decodable {
    let status: String
    let message: String?
    let deletedPath: String?
}

struct FileMoveResponse: Decodable {
    let status: String
    let message: String?
    let sourcePath: String?
    let destinationPath: String?
}

struct FileRenameResponse: Decodable {
    let status: String
    let message: String?
    let oldPath: String?
    let newPath: String?
    let newName: String?
}

struct FileCreateFolderResponse: Decodable {
    let status: String
    let message: String?
    let path: String?
}

// MARK: - Subtitles

struct SubtitleDownloadResponse: Decodable {
    let status: String
    let message: String?
    let subtitlePath: String?
}

struct SubtitleMergeResponse: Decodable {
    let status: String
    let message: String?
    let outputPath: String?
}

struct SubtitleGenerateResponse: Decodable {
    let status: String
    let message: String?
    let subtitlePath: String?
    let outputPath: String?
    let macService: GeneratedSubtitleMacService?
    let transcription: GeneratedSubtitleTranscription?
}

struct SubtitleGenerateJobResponse: Decodable {
    let status: String
    let job: SubtitleGenerateJob?
}

struct SubtitleGenerateJob: Decodable, Identifiable {
    let id: String
    let state: String
    let activeStage: String?
    let stageLabel: String?
    let progressPercent: Int?
    let stageProgressPercent: Int?
    let detail: String?
    let message: String?
    let videoPath: String?
    let subtitlePath: String?
    let outputPath: String?
    let startedAt: String?
    let updatedAt: String?
    let elapsedSeconds: Double?
    let error: String?
    let macService: GeneratedSubtitleMacService?
    let transcription: GeneratedSubtitleTranscription?

    var progressFraction: Double {
        min(max(Double(progressPercent ?? 0) / 100.0, 0), 1)
    }

    var isTerminal: Bool {
        state == "completed" || state == "failed"
    }
}

struct GeneratedSubtitleMacService: Decodable {
    let hostname: String?
    let baseUrl: String?
    let healthUrl: String?
    let version: String?
}

struct GeneratedSubtitleTranscription: Decodable {
    let requestedLanguage: String?
    let detectedLanguage: String?
    let segmentCount: Int?
    let model: String?
}

struct MacServiceStatusResponse: Decodable {
    let status: String
    let service: MacServiceStatus?
}

struct MacServiceStatus: Decodable {
    let name: String?
    let registered: Bool?
    let online: Bool?
    let heartbeatFresh: Bool?
    let lastSeen: String?
    let lastSeenAgeSeconds: Double?
    let staleAfterSeconds: Double?
    let hostname: String?
    let instanceId: String?
    let version: String?
    let baseUrl: String?
    let healthUrl: String?
    let port: Int?
    let addresses: [String]?
    let healthReachable: Bool?
    let health: MacServiceHealth?
    let healthError: String?
}

struct MacServiceHealth: Decodable {
    let status: String?
    let service: String?
    let version: String?
}

// MARK: - Queue Download

struct QueueDownloadResponse: Decodable {
    let status: String
    let message: String?
    let downloader: String?
    let gid: String?
    let directory: String?
    let stagingDirectory: String?
    let fileName: String?
}

struct FinalizeDownloadResponse: Decodable {
    let status: String
    let message: String?
    let downloader: String?
    let download: DownloadInfo?
}

// MARK: - Download Status

struct DownloadStatusResponse: Decodable {
    let status: String
    let downloader: String?
    let download: DownloadInfo?
}

struct DownloadInfo: Decodable {
    let requestedGid: String?
    let gid: String?
    let state: String?
    let infoHash: String?
    let totalBytes: Int64?
    let completedBytes: Int64?
    let downloadSpeedBytesPerSecond: Int64?
    let directory: String?
    let primaryPath: String?
    let stagingDirectory: String?
    let name: String?
    let metadataGid: String?
    let followedBy: [String]?
    let fileSelection: DownloadFileSelection?
    let finalization: DownloadFinalization?
    let cleanup: DownloadCleanup?

    var isMetadataPhase: Bool {
        if metadataGid != nil && gid == requestedGid {
            return true
        }
        if let primaryPath, primaryPath.hasPrefix("[METADATA]") {
            return true
        }
        return false
    }

    var progress: Double {
        guard let totalBytes, totalBytes > 0, let completedBytes else { return 0 }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    var formattedSpeed: String {
        guard let speed = downloadSpeedBytesPerSecond, speed > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: speed))/s"
    }

    var estimatedTimeRemaining: String {
        guard let totalBytes, totalBytes > 0,
              let completedBytes,
              let speed = downloadSpeedBytesPerSecond, speed > 0 else { return "—" }
        let remaining = totalBytes - completedBytes
        guard remaining > 0 else { return "0s" }
        let seconds = Int(remaining / speed)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return "\(h)h \(m)m"
    }

    var formattedProgress: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let completed = formatter.string(fromByteCount: completedBytes ?? 0)
        if let totalBytes, totalBytes > 0 {
            let total = formatter.string(fromByteCount: totalBytes)
            return "\(completed) / \(total)"
        }
        return completed
    }

    var displayName: String {
        if let finalPath = finalization?.finalPath, !finalPath.isEmpty {
            return (finalPath as NSString).lastPathComponent
        }
        if let destinationPath = finalization?.destinationPath, !destinationPath.isEmpty {
            return (destinationPath as NSString).lastPathComponent
        }
        if let primaryPath, !primaryPath.isEmpty, !primaryPath.hasPrefix("[METADATA]") {
            return (primaryPath as NSString).lastPathComponent
        }
        if let name, !name.isEmpty { return name }
        return gid ?? "Download"
    }

    var displayDirectory: String? {
        if let finalPath = finalization?.finalPath, !finalPath.isEmpty {
            return (finalPath as NSString).deletingLastPathComponent
        }
        if let targetDirectory = finalization?.targetDirectory, !targetDirectory.isEmpty {
            return targetDirectory
        }
        return directory
    }

    var displayPrimaryPath: String? {
        if let finalPath = finalization?.finalPath, !finalPath.isEmpty {
            return finalPath
        }
        return primaryPath
    }

    var hasDownloadedAllBytes: Bool {
        guard let totalBytes, totalBytes > 0, let completedBytes else { return false }
        return completedBytes >= totalBytes
    }

    var finalizationState: String {
        finalization?.state ?? "not_requested"
    }

    var isFinalizationInProgress: Bool {
        switch finalizationState {
        case "queued", "in_progress":
            return true
        default:
            return false
        }
    }

    var isFinalizationCompleted: Bool {
        finalizationState == "completed"
    }

    var isFinalizationError: Bool {
        finalizationState == "error"
    }

    var isReadyForFinalization: Bool {
        hasDownloadedAllBytes && !isMetadataPhase && !isError
    }

    var isAwaitingFinalization: Bool {
        isReadyForFinalization && !isFinalizationInProgress && !isFinalizationCompleted && !isFinalizationError
    }

    var isTerminalForUI: Bool {
        isError || isFinalizationCompleted || isFinalizationError
    }

    var cleanupState: String {
        cleanup?.state ?? "not_requested"
    }

    var isCleanupInProgress: Bool {
        cleanupState == "in_progress"
    }

    var isCleanupCompleted: Bool {
        cleanupState == "completed"
    }

    var isCleanupError: Bool {
        cleanupState == "error"
    }

    var canDeleteTempFiles: Bool {
        isFinalizationCompleted && !isCleanupCompleted && !isCleanupInProgress
    }

    var isComplete: Bool { state == "complete" }
    var isError: Bool { state == "error" }
    var isActive: Bool { state == "active" || state == "waiting" || state == "paused" }
}

struct DownloadFileSelection: Decodable {
    let state: String?
    let message: String?
    let selectedFile: DownloadSelectedFile?
    let renameTarget: DownloadRenameTarget?

    var displayState: String {
        guard let state, !state.isEmpty else { return "Pending" }
        return state
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

struct DownloadSelectedFile: Decodable {
    let index: String?
    let name: String?
    let path: String?
    let sizeBytes: Int64?

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        if let path, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return "Selected video file"
    }
}

struct DownloadRenameTarget: Decodable {
    let requestedName: String?
    let fileName: String?
    let appliesToIndex: String?
}

struct DownloadFinalization: Decodable {
    let state: String?
    let message: String?
    let mode: String?
    let stagingDirectory: String?
    let targetDirectory: String?
    let sourcePath: String?
    let destinationPath: String?
    let totalBytes: Int64?
    let completedBytes: Int64?
    let finalPath: String?

    var progress: Double {
        guard let totalBytes, totalBytes > 0, let completedBytes else { return 0 }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    var formattedProgress: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let completed = formatter.string(fromByteCount: completedBytes ?? 0)
        if let totalBytes, totalBytes > 0 {
            let total = formatter.string(fromByteCount: totalBytes)
            return "\(completed) / \(total)"
        }
        return completed
    }
}

struct DownloadCleanup: Decodable {
    let state: String?
    let message: String?
    let deletedPaths: [String]?
}
