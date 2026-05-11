//
//  InfoViewModel.swift
//  BiffDownload
//

import Combine
import Foundation
import os

@MainActor
final class InfoViewModel: ObservableObject {
    @Published private(set) var disk: DiskInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var hasLoaded = false

    private var apiService: APIService?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BiffDownload",
        category: "Info"
    )

    var isConfigured: Bool {
        apiService != nil
    }

    func configure(baseURL: URL) {
        if apiService?.baseURL == baseURL {
            return
        }

        apiService = APIService(baseURL: baseURL)
        disk = nil
        errorMessage = nil
        lastUpdatedAt = nil
        hasLoaded = false
        logger.info("Configured info API baseURL=\(baseURL.absoluteString, privacy: .public)")
    }

    func refresh() async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            logger.error("Disk info requested without an API service.")
            return
        }

        isLoading = true
        errorMessage = nil
        logger.info("Loading disk info")

        defer {
            isLoading = false
        }

        do {
            let response = try await apiService.disk()
            guard let disk = response.disk else {
                errorMessage = "Server did not return disk information."
                logger.error("Disk info response did not include a disk payload.")
                return
            }

            self.disk = disk
            lastUpdatedAt = Date()
            hasLoaded = true
            logger.info(
                "Loaded disk info path=\(disk.path, privacy: .public) percentUsed=\(disk.percentUsed ?? -1, privacy: .public)"
            )
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Disk info load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
