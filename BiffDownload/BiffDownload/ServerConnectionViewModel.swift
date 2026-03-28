//
//  ServerConnectionViewModel.swift
//  BiffDownload
//
//  Created by Codex on 3/28/26.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ServerConnectionViewModel: ObservableObject {
    @Published private(set) var appName = "BiffDownload"
    @Published private(set) var configSourceLabel = "Not loaded"
    @Published private(set) var serverName = "Not configured"
    @Published private(set) var discoverySummary = "No server hosts configured"
    @Published private(set) var fallbackIPAddress = "Not configured"
    @Published private(set) var bundledFallbackIPAddress = "Not configured"
    @Published private(set) var ipOverrideStatus = "Using bundled config IP"
    @Published private(set) var isConnected = false
    @Published private(set) var connectedIPAddress: String?
    @Published private(set) var connectedHost: String?
    @Published private(set) var resolvedAPIBaseURLString: String?
    @Published private(set) var resolvedAPIBaseURL: URL?
    @Published private(set) var statusTitle = "Loading configuration"
    @Published private(set) var statusMessage = "Looking for a bundled app config."
    @Published private(set) var lastError: String?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var isConnecting = false
    @Published private(set) var canConnect = false

    private let loader: AppConfigLoader
    private let session: URLSession
    private let userDefaults: UserDefaults
    private let manualIPAddressDefaultsKey = "BiffDownload.manualIPAddressOverride"
    private var loadedConfig: LoadedAppConfig?
    private var hasAttemptedLaunchConnection = false

    init() {
        loader = AppConfigLoader()
        userDefaults = .standard

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)

        loadConfig()
    }

    var statusSymbolName: String {
        if isConnecting {
            return "dot.radiowaves.left.and.right"
        }

        if isConnected {
            return "checkmark.circle.fill"
        }

        return lastError == nil ? "gearshape.fill" : "exclamationmark.triangle.fill"
    }

    var statusColor: Color {
        if isConnecting {
            return .yellow
        }

        return isConnected ? .green : .orange
    }

    func connectOnLaunchIfNeeded() async {
        guard !hasAttemptedLaunchConnection else {
            return
        }

        hasAttemptedLaunchConnection = true

        guard loadedConfig?.config.polling.healthCheckOnLaunch ?? false else {
            return
        }

        await refreshConnection()
    }

    func refreshConnection() async {
        if loadedConfig == nil {
            loadConfig()
        }

        guard let loadedConfig else {
            statusTitle = "Configuration missing"
            statusMessage = "Add apple-tv.config.local.json to the app bundle or keep the example config in place."
            lastError = "The app could not load a configuration file."
            isConnected = false
            connectedIPAddress = nil
            connectedHost = nil
            resolvedAPIBaseURLString = nil
            resolvedAPIBaseURL = nil
            lastCheckedAt = Date()
            return
        }

        let config = loadedConfig.config
        let candidates = connectionCandidates(for: config.server)

        isConnecting = true
        lastError = nil
        isConnected = false
        connectedIPAddress = nil
        connectedHost = nil
        resolvedAPIBaseURLString = nil
        resolvedAPIBaseURL = nil
        statusTitle = "Resolving server"
        statusMessage = candidates.isEmpty
            ? "No hostname or IP candidates were found in the config."
            : "Trying \(candidates.joined(separator: ", "))."

        defer {
            isConnecting = false
            lastCheckedAt = Date()
        }

        for candidate in candidates {
            if let resolvedServer = await probeServer(host: candidate, config: config) {
                isConnected = true
                connectedIPAddress = resolvedServer.connectedIPAddress
                connectedHost = resolvedServer.connectedHost
                resolvedAPIBaseURLString = resolvedServer.apiBaseURL.absoluteString
                resolvedAPIBaseURL = resolvedServer.apiBaseURL
                statusTitle = "Connected"
                statusMessage = "Connected to \(resolvedServer.connectedHost)."
                return
            }
        }

        statusTitle = "Connection failed"
        statusMessage = "The Apple TV could not reach the server using the configured hostnames or fallback IP."
        lastError = "Hostname lookup for DESKTOP-SB0Q7M3 only works when that machine is resolvable on the LAN, usually through Bonjour/mDNS or local DNS. The app fell back to the configured IP after that."
    }

    private func loadConfig() {
        do {
            let loadedConfig = try loader.load()
            self.loadedConfig = loadedConfig
            refreshConfigDisplay()
            statusTitle = "Configuration loaded"
            statusMessage = "Using \(loadedConfig.source.displayName) for LAN server discovery."
            lastError = nil
        } catch {
            self.loadedConfig = nil
            canConnect = false
            configSourceLabel = "Missing"
            serverName = "Not configured"
            discoverySummary = "No server hosts configured"
            fallbackIPAddress = "Not configured"
            bundledFallbackIPAddress = "Not configured"
            ipOverrideStatus = "Using bundled config IP"
            isConnected = false
            statusTitle = "Configuration missing"
            statusMessage = "Add apple-tv.config.local.json to the app bundle to override the example config."
            lastError = error.localizedDescription
        }
    }

    func currentIPAddressOctets() -> [String] {
        let ipAddress = effectiveFallbackIPAddress() ?? ""
        let octets = ipAddress.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        guard octets.count == 4 else {
            return ["", "", "", ""]
        }

        return octets
    }

    func setManualIPAddress(_ ipAddress: String) {
        let normalizedIPAddress = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        userDefaults.set(normalizedIPAddress, forKey: manualIPAddressDefaultsKey)
        refreshConfigDisplay()
    }

    private func probeServer(host: String, config: AppConfig) async -> ResolvedServer? {
        guard let systemURL = config.server.apiURL(for: host, endpointPath: config.endpoints.system),
              let apiBaseURL = config.server.apiBaseURL(for: host) else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: systemURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(SystemResponse.self, from: data)
            let connectedIPAddress = payload.connectedIPAddress(fallbackHost: host)

            return ResolvedServer(
                connectedHost: host,
                connectedIPAddress: connectedIPAddress,
                apiBaseURL: apiBaseURL
            )
        } catch {
            return nil
        }
    }

    private func refreshConfigDisplay() {
        guard let loadedConfig else {
            return
        }

        let config = loadedConfig.config
        let connectionCandidates = connectionCandidates(for: config.server)
        let savedIPAddressOverride = manualIPAddressOverride()

        appName = config.appName
        configSourceLabel = loadedConfig.source.displayName
        serverName = config.server.name ?? config.server.hostname ?? config.server.lanIp ?? "Not configured"
        discoverySummary = connectionCandidates.isEmpty
            ? "No server hosts configured"
            : connectionCandidates.joined(separator: " -> ")
        bundledFallbackIPAddress = config.server.lanIp ?? "Not configured"
        fallbackIPAddress = effectiveFallbackIPAddress(for: config.server) ?? "Not configured"
        ipOverrideStatus = savedIPAddressOverride.map { "Custom override saved: \($0)" } ?? "Using bundled config IP"
        canConnect = !connectionCandidates.isEmpty
    }

    private func connectionCandidates(for server: AppConfig.Server) -> [String] {
        var seen = Set<String>()
        var candidates: [String] = []

        func append(_ value: String?) {
            guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
                return
            }

            let normalizedValue = rawValue.lowercased()
            guard seen.insert(normalizedValue).inserted else {
                return
            }

            candidates.append(rawValue)
        }

        server.hostnameCandidates?.forEach(append)
        append(server.hostname)
        append(manualIPAddressOverride() ?? server.lanIp)

        let apiBaseHost = URL(string: server.apiBaseUrl ?? "")?.host
        if manualIPAddressOverride() == nil || apiBaseHost != server.lanIp {
            append(apiBaseHost)
        }

        return candidates
    }

    private func effectiveFallbackIPAddress(for server: AppConfig.Server? = nil) -> String? {
        if let manualIPAddressOverride = manualIPAddressOverride() {
            return manualIPAddressOverride
        }

        return server?.lanIp ?? loadedConfig?.config.server.lanIp
    }

    private func manualIPAddressOverride() -> String? {
        guard let rawIPAddress = userDefaults.string(forKey: manualIPAddressDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              isIPv4Address(rawIPAddress) else {
            return nil
        }

        return rawIPAddress
    }

    private func isIPv4Address(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        guard components.count == 4 else {
            return false
        }

        return components.allSatisfy { component in
            guard let octet = Int(component), (0...255).contains(octet) else {
                return false
            }

            return String(octet) == component || (octet == 0 && component == "0")
        }
    }
}

private struct ResolvedServer {
    let connectedHost: String
    let connectedIPAddress: String?
    let apiBaseURL: URL
}

private struct SystemResponse: Decodable {
    struct SystemPayload: Decodable {
        struct APIPayload: Decodable {
            let lanUrl: String?
        }

        let hostname: String?
        let lanIPv4: [String]?
        let preferredLanIp: String?
        let api: APIPayload?
    }

    let system: SystemPayload

    func connectedIPAddress(fallbackHost: String) -> String? {
        if let preferredLanIp = system.preferredLanIp, !preferredLanIp.isEmpty {
            return preferredLanIp
        }

        if let apiLanURL = system.api?.lanUrl,
           let host = URL(string: apiLanURL)?.host,
           !host.isEmpty {
            return host
        }

        if let firstLanIP = system.lanIPv4?.first, !firstLanIP.isEmpty {
            return firstLanIP
        }

        return isIPv4Address(fallbackHost) ? fallbackHost : nil
    }

    private func isIPv4Address(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        guard components.count == 4 else {
            return false
        }

        return components.allSatisfy { component in
            guard let octet = Int(component), (0...255).contains(octet) else {
                return false
            }

            return String(octet) == component || (octet == 0 && component == "0")
        }
    }
}
