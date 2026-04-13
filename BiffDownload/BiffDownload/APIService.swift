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
        config.timeoutIntervalForResource = 30
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
