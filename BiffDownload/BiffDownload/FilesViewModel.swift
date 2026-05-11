//
//  FilesViewModel.swift
//  BiffDownload
//

import Combine
import Foundation
import os

struct FileDestinationChoice: Identifiable, Hashable {
    let path: String
    let name: String
    let detail: String

    var id: String {
        path.isEmpty ? "__root__" : path
    }
}

@MainActor
final class FilesViewModel: ObservableObject {
    @Published private(set) var root: String?
    @Published private(set) var currentPath = ""
    @Published private(set) var absolutePath: String?
    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var hasLoaded = false
    @Published var selectedEntry: FileEntry?

    private var apiService: APIService?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BiffDownload",
        category: "Files"
    )

    var isConfigured: Bool {
        apiService != nil
    }

    var pathDisplayName: String {
        currentPath.isEmpty ? "Download Root" : currentPath
    }

    var canGoUp: Bool {
        !currentPath.isEmpty
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
        selectedEntry = nil
        errorMessage = nil
        statusMessage = nil
        hasLoaded = false
        logger.info("Configured files API baseURL=\(baseURL.absoluteString, privacy: .public)")
    }

    func loadRoot() async {
        await load(path: "")
    }

    func refresh() async {
        await load(path: currentPath)
    }

    func openSelectedFolder() async {
        guard let selectedEntry, selectedEntry.isDirectory else { return }
        await load(path: selectedEntry.relativePath)
    }

    func openFolder(_ entry: FileEntry) async {
        guard entry.isDirectory else { return }
        await load(path: entry.relativePath)
    }

    func goUp() async {
        guard canGoUp else { return }
        await load(path: parentPath(of: currentPath))
    }

    func select(_ entry: FileEntry) {
        selectedEntry = entry
        clearMessages()
    }

    func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    func delete(_ entry: FileEntry) async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            return
        }

        isWorking = true
        errorMessage = nil
        statusMessage = nil
        logger.info("Deleting file path=\(entry.relativePath, privacy: .public)")

        defer {
            isWorking = false
        }

        do {
            let response = try await apiService.deleteFile(path: entry.relativePath)
            selectedEntry = nil
            statusMessage = response.message ?? "Deleted \(entry.name)."
            logger.info(
                "Deleted file path=\(response.deletedPath ?? entry.relativePath, privacy: .public)"
            )
            await load(path: currentPath, preserveStatus: true)
        } catch {
            errorMessage = error.localizedDescription
            logger.error(
                "Delete failed path=\(entry.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func move(_ entry: FileEntry, destination: String) async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            return
        }

        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSamePath(trimmedDestination, parentPath(of: entry.relativePath)) else {
            errorMessage = "Choose a different destination folder."
            return
        }

        isWorking = true
        errorMessage = nil
        statusMessage = nil
        logger.info(
            "Moving file source=\(entry.relativePath, privacy: .public) destination=\(trimmedDestination, privacy: .public)"
        )

        defer {
            isWorking = false
        }

        do {
            let response = try await apiService.moveFile(
                source: entry.relativePath,
                destination: trimmedDestination
            )
            selectedEntry = nil
            statusMessage = response.message ?? "Moved \(entry.name)."
            logger.info(
                "Moved file source=\(response.sourcePath ?? entry.relativePath, privacy: .public) destination=\(response.destinationPath ?? trimmedDestination, privacy: .public)"
            )
            await load(path: currentPath, preserveStatus: true)
        } catch {
            errorMessage = error.localizedDescription
            logger.error(
                "Move failed source=\(entry.relativePath, privacy: .public) destination=\(trimmedDestination, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func rename(_ entry: FileEntry, name: String) async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a new name."
            return
        }

        guard !trimmedName.contains("\\") && !trimmedName.contains("/") else {
            errorMessage = "The new name cannot contain path separators."
            return
        }

        isWorking = true
        errorMessage = nil
        statusMessage = nil
        logger.info(
            "Renaming file path=\(entry.relativePath, privacy: .public) name=\(trimmedName, privacy: .public)"
        )

        defer {
            isWorking = false
        }

        do {
            let response = try await apiService.renameFile(path: entry.relativePath, name: trimmedName)
            statusMessage = response.message ?? "Renamed \(entry.name)."
            logger.info(
                "Renamed file oldPath=\(response.oldPath ?? entry.relativePath, privacy: .public) newPath=\(response.newPath ?? "<unknown>", privacy: .public)"
            )
            await load(path: currentPath, preserveStatus: true)

            if let newPath = response.newPath,
               let renamedEntry = entries.first(where: { isSamePath($0.relativePath, newPath) }) {
                selectedEntry = renamedEntry
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error(
                "Rename failed path=\(entry.relativePath, privacy: .public) name=\(trimmedName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func createFolder(name: String) async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a folder name."
            return
        }

        let invalidCharacters = CharacterSet(charactersIn: "<>:\"/\\|?*")
        guard trimmedName.rangeOfCharacter(from: invalidCharacters) == nil else {
            errorMessage = "Folder names cannot contain < > : \" / \\ | ? *."
            return
        }

        isWorking = true
        errorMessage = nil
        statusMessage = nil
        logger.info(
            "Creating folder path=\(self.currentPath, privacy: .public) name=\(trimmedName, privacy: .public)"
        )

        defer {
            isWorking = false
        }

        do {
            let response = try await apiService.createFolder(path: currentPath, name: trimmedName)
            statusMessage = response.message ?? "Created \(trimmedName)."
            logger.info(
                "Created folder path=\(response.path ?? "<unknown>", privacy: .public)"
            )
            await load(path: currentPath, preserveStatus: true)

            if let createdPath = response.path,
               let createdEntry = entries.first(where: { isSamePath($0.relativePath, createdPath) }) {
                selectedEntry = createdEntry
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error(
                "Create folder failed path=\(self.currentPath, privacy: .public) name=\(trimmedName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func destinationChoices(for entry: FileEntry) -> [FileDestinationChoice] {
        var choices: [FileDestinationChoice] = [
            FileDestinationChoice(path: "", name: "Download Root", detail: root ?? "Root folder")
        ]

        if canGoUp {
            let parent = parentPath(of: currentPath)
            choices.append(
                FileDestinationChoice(
                    path: parent,
                    name: parent.isEmpty ? "Parent: Download Root" : "Parent: \(lastPathComponent(parent))",
                    detail: parent.isEmpty ? "Download Root" : parent
                )
            )
        }

        let directories = entries
            .filter { $0.isDirectory }
            .filter { !isSamePath($0.relativePath, entry.relativePath) }
            .filter { !entry.isDirectory || !isDescendant(path: $0.relativePath, of: entry.relativePath) }

        for directory in directories {
            choices.append(
                FileDestinationChoice(
                    path: directory.relativePath,
                    name: directory.name,
                    detail: directory.relativePath
                )
            )
        }

        return choices.removingDuplicatePaths()
    }

    private func load(path: String, preserveStatus: Bool = false) async {
        guard let apiService else {
            errorMessage = "Not connected to server."
            logger.error("Files load requested without an API service.")
            return
        }

        isLoading = true
        errorMessage = nil
        if !preserveStatus {
            statusMessage = nil
        }
        logger.info("Loading files path=\(path, privacy: .public)")

        defer {
            isLoading = false
        }

        do {
            let response = try await apiService.files(path: path)
            root = response.root
            currentPath = response.path ?? path
            absolutePath = response.absolutePath
            entries = response.entries ?? []
            hasLoaded = true
            selectedEntry = selectedEntry.flatMap { selected in
                entries.first(where: { isSamePath($0.relativePath, selected.relativePath) })
            }
            logger.info(
                "Loaded files path=\(self.currentPath, privacy: .public) count=\(self.entries.count)"
            )
        } catch {
            errorMessage = error.localizedDescription
            logger.error(
                "Files load failed path=\(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func parentPath(of path: String) -> String {
        let parts = pathComponents(path)
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "\\")
    }

    private func lastPathComponent(_ path: String) -> String {
        pathComponents(path).last ?? path
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

    private func isDescendant(path: String, of ancestor: String) -> Bool {
        let candidatePath = normalizedPath(path)
        let normalizedAncestor = normalizedPath(ancestor)
        guard !normalizedAncestor.isEmpty else { return true }
        return candidatePath.hasPrefix(normalizedAncestor + "\\")
    }
}

private extension Array where Element == FileDestinationChoice {
    func removingDuplicatePaths() -> [FileDestinationChoice] {
        var seen = Set<String>()
        var result: [FileDestinationChoice] = []

        for choice in self {
            let key = choice.path
                .split { character in
                    character == "\\" || character == "/"
                }
                .joined(separator: "\\")
                .lowercased()

            if seen.insert(key).inserted {
                result.append(choice)
            }
        }

        return result
    }
}
