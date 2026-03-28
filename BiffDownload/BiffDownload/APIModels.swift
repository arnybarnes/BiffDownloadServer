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

// MARK: - Queue Download

struct QueueDownloadResponse: Decodable {
    let status: String
    let message: String?
    let downloader: String?
    let gid: String?
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
    let name: String?
    let metadataGid: String?
    let followedBy: [String]?

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
        return Double(completedBytes) / Double(totalBytes)
    }

    var formattedSpeed: String {
        guard let speed = downloadSpeedBytesPerSecond, speed > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: speed))/s"
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
        if let name, !name.isEmpty { return name }
        if let primaryPath, !primaryPath.isEmpty, !primaryPath.hasPrefix("[METADATA]") {
            return (primaryPath as NSString).lastPathComponent
        }
        return gid ?? "Download"
    }

    var isComplete: Bool { state == "complete" }
    var isError: Bool { state == "error" }
    var isActive: Bool { state == "active" || state == "waiting" || state == "paused" }
}
