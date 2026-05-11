//
//  AppConfig.swift
//  BiffDownload
//
//  Created by Codex on 3/28/26.
//

import Foundation

struct AppConfig: Decodable {
    let appName: String
    let environment: String
    let server: Server
    let endpoints: Endpoints
    let polling: Polling

    struct Server: Decodable {
        let name: String?
        let hostname: String?
        let hostnameCandidates: [String]?
        let lanIp: String?
        let apiPort: Int
        let webPort: Int
        let apiBaseUrl: String?
        let webUrl: String?

        var connectionCandidates: [String] {
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

            hostnameCandidates?.forEach(append)
            append(hostname)
            append(lanIp)
            append(URL(string: apiBaseUrl ?? "")?.host)

            return candidates
        }

        var apiScheme: String {
            URL(string: apiBaseUrl ?? "")?.scheme ?? "http"
        }

        func apiBaseURL(for host: String) -> URL? {
            var components = URLComponents()
            components.scheme = apiScheme
            components.host = host
            components.port = apiPort
            return components.url
        }

        func apiURL(for host: String, endpointPath: String) -> URL? {
            guard let baseURL = apiBaseURL(for: host),
                  var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                return nil
            }

            components.scheme = apiScheme
            components.host = host
            components.port = apiPort
            components.path = endpointPath.hasPrefix("/") ? endpointPath : "/\(endpointPath)"
            return components.url
        }
    }

    struct Endpoints: Decodable {
        let health: String
        let system: String
        let restart: String
        let search: String
        let disk: String
        let queueDownload: String
        let downloadStatus: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            health = try container.decode(String.self, forKey: .health)
            system = try container.decode(String.self, forKey: .system)
            restart = try container.decodeIfPresent(String.self, forKey: .restart) ?? "/api/v1/system/restart"
            search = try container.decode(String.self, forKey: .search)
            disk = try container.decodeIfPresent(String.self, forKey: .disk) ?? "/api/v1/disk"
            queueDownload = try container.decode(String.self, forKey: .queueDownload)
            downloadStatus = try container.decode(String.self, forKey: .downloadStatus)
        }

        private enum CodingKeys: String, CodingKey {
            case health, system, restart, search, disk, queueDownload, downloadStatus
        }
    }

    struct Polling: Decodable {
        let downloadStatusIntervalSeconds: Int
        let healthCheckOnLaunch: Bool
    }
}

enum AppConfigSource: String {
    case local
    case example

    var resourceName: String {
        switch self {
        case .local:
            return "apple-tv.config.local"
        case .example:
            return "apple-tv.config.example"
        }
    }

    var displayName: String {
        switch self {
        case .local:
            return "apple-tv.config.local.json"
        case .example:
            return "apple-tv.config.example.json"
        }
    }
}

struct LoadedAppConfig {
    let config: AppConfig
    let source: AppConfigSource
}

enum AppConfigLoaderError: LocalizedError {
    case missingBundledConfig
    case unreadableConfig(URL, Error)

    var errorDescription: String? {
        switch self {
        case .missingBundledConfig:
            return "No bundled app configuration file was found."
        case let .unreadableConfig(url, error):
            return "Could not decode \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

struct AppConfigLoader {
    func load(bundle: Bundle = .main) throws -> LoadedAppConfig {
        for source in [AppConfigSource.local, AppConfigSource.example] {
            guard let url = bundle.url(forResource: source.resourceName, withExtension: "json") else {
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(AppConfig.self, from: data)
                return LoadedAppConfig(config: config, source: source)
            } catch {
                throw AppConfigLoaderError.unreadableConfig(url, error)
            }
        }

        throw AppConfigLoaderError.missingBundledConfig
    }
}
