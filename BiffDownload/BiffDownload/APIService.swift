//
//  APIService.swift
//  BiffDownload
//

import Foundation

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

struct APIService {
    let baseURL: URL
    private let session: URLSession

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

    // MARK: - Queue Download

    func queueDownload(resultId: String) async throws -> QueueDownloadResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/v1/downloads"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["resultId": resultId])

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

    // MARK: - Private

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8)
            throw APIError.httpError(httpResponse.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
