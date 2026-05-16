//
//  APIService.swift
//  BiffDownload
//

import Foundation
import os

enum APIError: LocalizedError {
    case notConnected
    case invalidURL
    case httpError(Int, String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server."
        case .invalidURL:
            return "Could not build request URL."
        case let .httpError(code, message):
            return "Server returned \(code)\(message.map { ": \($0)" } ?? "")."
        case let .decodingError(error):
            return "Failed to read server response: \(error.localizedDescription)"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

private struct QueueDownloadRequest: Encodable {
    let resultId: String?
    let folder: String?
    let fileName: String?
}

private struct DeleteFileRequest: Encodable {
    let path: String
}

private struct MoveFileRequest: Encodable {
    let source: String
    let destination: String
}

private struct RenameFileRequest: Encodable {
    let path: String
    let name: String
}

private struct CreateFolderRequest: Encodable {
    let path: String
    let name: String
}

private struct SubtitleDownloadRequest: Encodable {
    let path: String
    let name: String
    let language: String
}

private struct SubtitleMergeRequest: Encodable {
    let videoPath: String
    let subtitlePath: String
}

private struct SubtitleGenerateRequest: Encodable {
    let videoPath: String
    let language: String?
}

struct APIService {
    let baseURL: URL
    private let session: URLSession
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BiffDownload",
        category: "API"
    )

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    // MARK: - Search

    func search(query: String) async throws -> SearchResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else { throw APIError.invalidURL }

        return try await perform(URLRequest(url: url))
    }

    // MARK: - Download Folders

    func downloadFolders() async throws -> DownloadFoldersResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/download-folders"

        guard let url = components.url else { throw APIError.invalidURL }

        return try await perform(URLRequest(url: url))
    }

    // MARK: - Disk

    func disk() async throws -> DiskResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/disk"

        guard let url = components.url else { throw APIError.invalidURL }

        return try await perform(URLRequest(url: url))
    }

    // MARK: - Files

    func files(path: String = "") async throws -> FileListResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/files"
        if !path.isEmpty {
            components.queryItems = [URLQueryItem(name: "path", value: path)]
        }

        guard let url = components.url else { throw APIError.invalidURL }

        return try await perform(URLRequest(url: url))
    }

    func deleteFile(path: String) async throws -> FileDeleteResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/files/delete"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeleteFileRequest(path: path))

        return try await perform(request)
    }

    func moveFile(source: String, destination: String) async throws -> FileMoveResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/files/move"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MoveFileRequest(source: source, destination: destination)
        )

        return try await perform(request)
    }

    func renameFile(path: String, name: String) async throws -> FileRenameResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/files/rename"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RenameFileRequest(path: path, name: name)
        )

        return try await perform(request)
    }

    func createFolder(path: String, name: String) async throws -> FileCreateFolderResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/files/create-folder"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CreateFolderRequest(path: path, name: name)
        )

        return try await perform(request)
    }

    // MARK: - Subtitles

    func downloadSubtitle(path: String, name: String, language: String = "en") async throws -> SubtitleDownloadResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/subtitles/download"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SubtitleDownloadRequest(path: path, name: name, language: language)
        )

        return try await perform(request)
    }

    func mergeSubtitle(videoPath: String, subtitlePath: String) async throws -> SubtitleMergeResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/subtitles/merge"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SubtitleMergeRequest(videoPath: videoPath, subtitlePath: subtitlePath)
        )

        return try await perform(request)
    }

    func generateSubtitle(videoPath: String, language: String? = nil) async throws -> SubtitleGenerateResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/subtitles/generate"

        guard let url = components.url else { throw APIError.invalidURL }

        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLanguage = trimmedLanguage?.isEmpty == false ? trimmedLanguage : nil

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SubtitleGenerateRequest(videoPath: videoPath, language: normalizedLanguage)
        )

        return try await perform(request)
    }

    func macServiceStatus() async throws -> MacServiceStatusResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/services/mac-api"

        guard let url = components.url else { throw APIError.invalidURL }

        return try await perform(URLRequest(url: url))
    }

    // MARK: - Queue Download

    func queueDownload(
        resultId: String,
        folder: String? = nil,
        fileName: String? = nil
    ) async throws -> QueueDownloadResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/downloads"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            QueueDownloadRequest(
                resultId: resultId,
                folder: folder,
                fileName: fileName
            )
        )

        return try await perform(request)
    }

    // MARK: - Download Status

    func downloadStatus(gid: String) async throws -> DownloadStatusResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/downloads/\(gid)"

        guard let url = components.url else { throw APIError.invalidURL }

        return try await perform(URLRequest(url: url))
    }

    func finalizeDownload(gid: String) async throws -> FinalizeDownloadResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/downloads/\(gid)/finalize"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        return try await perform(request)
    }

    func deleteTempFiles(gid: String) async throws -> FinalizeDownloadResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/downloads/\(gid)/cleanup"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        return try await perform(request)
    }

    // MARK: - Private

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        Self.logger.debug(
            "Request method=\(request.httpMethod ?? "GET", privacy: .public) url=\(request.url?.absoluteString ?? "<nil>", privacy: .public)"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logger.error(
                "Network error method=\(request.httpMethod ?? "GET", privacy: .public) url=\(request.url?.absoluteString ?? "<nil>", privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw APIError.networkError(error)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        Self.logger.debug(
            "Response status=\(statusCode) bytes=\(data.count) url=\(request.url?.absoluteString ?? "<nil>", privacy: .public)"
        )

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8)
            Self.logger.error(
                "HTTP error status=\(httpResponse.statusCode) url=\(request.url?.absoluteString ?? "<nil>", privacy: .public) body=\(Self.bodyPreview(from: data), privacy: .public)"
            )
            throw APIError.httpError(httpResponse.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Self.logger.error(
                "Decoding error url=\(request.url?.absoluteString ?? "<nil>", privacy: .public): \(error.localizedDescription, privacy: .public) body=\(Self.bodyPreview(from: data), privacy: .public)"
            )
            throw APIError.decodingError(error)
        }
    }

    private static func bodyPreview(from data: Data) -> String {
        let decodedBody = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
        return String(decodedBody.prefix(400))
    }
}
