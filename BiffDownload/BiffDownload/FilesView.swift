//
//  FilesView.swift
//  BiffDownload
//

import SwiftUI

struct FilesView: View {
    private enum DetailFocusTarget: Hashable {
        case parent
        case createFolder
        case open
        case rename
        case move
        case delete
    }

    private enum ModalFocusTarget: Hashable {
        case createFolderName
        case createFolderCancel
        case createFolderConfirm
        case renameName
        case renameCancel
        case renameConfirm
        case moveDestination
        case moveCancel
        case moveConfirm
        case deleteCancel
        case deleteConfirm
    }

    @ObservedObject var connectionModel: ServerConnectionViewModel
    @ObservedObject var viewModel: FilesViewModel
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var renameEntry: FileEntry?
    @State private var renameText = ""
    @State private var deleteEntry: FileEntry?
    @State private var moveEntry: FileEntry?
    @State private var moveDestination = ""
    @FocusState private var focusedDetailTarget: DetailFocusTarget?
    @FocusState private var focusedModalTarget: ModalFocusTarget?

    private var hasModalOpen: Bool {
        isCreatingFolder || renameEntry != nil || moveEntry != nil || deleteEntry != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                VStack(alignment: .leading, spacing: 24) {
                    header

                    if connectionModel.isConnected {
                        browserContent
                    } else {
                        disconnectedCard
                    }

                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(hasModalOpen)

                modalOverlay
                    .zIndex(2)
            }
            .navigationBarHidden(true)
            .task {
                await configureAndLoadIfNeeded()
            }
            .onChange(of: connectionModel.resolvedAPIBaseURL) { _ in
                Task {
                    await configureAndLoadIfNeeded(forceReload: true)
                }
            }
            .onChange(of: viewModel.selectedEntry?.id) { selectedID in
                if selectedID == nil {
                    focusedDetailTarget = nil
                }
            }
            .onChange(of: isCreatingFolder) { isCreating in
                if isCreating {
                    focusModal(.createFolderName)
                } else if !hasModalOpen {
                    focusedModalTarget = nil
                }
            }
            .onChange(of: renameEntry?.id) { entryID in
                if entryID != nil {
                    focusModal(.renameName)
                } else if !hasModalOpen {
                    focusedModalTarget = nil
                }
            }
            .onChange(of: moveEntry?.id) { entryID in
                if entryID != nil {
                    focusModal(.moveDestination)
                } else if !hasModalOpen {
                    focusedModalTarget = nil
                }
            }
            .onChange(of: deleteEntry?.id) { entryID in
                if entryID != nil {
                    focusModal(.deleteCancel)
                } else if !hasModalOpen {
                    focusedModalTarget = nil
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Files")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(viewModel.pathDisplayName)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 16) {
                Button {
                    viewModel.clearMessages()
                    newFolderName = ""
                    isCreatingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!connectionModel.isConnected || viewModel.isLoading || viewModel.isWorking)

                Button {
                    Task {
                        await viewModel.goUp()
                    }
                } label: {
                    Label("Up", systemImage: "chevron.up")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!connectionModel.isConnected || !viewModel.canGoUp || viewModel.isLoading)

                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Label(viewModel.isLoading ? "Loading..." : "Refresh", systemImage: "arrow.clockwise")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!connectionModel.isConnected || viewModel.isLoading)
            }
        }
    }

    private var browserContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            pathCard

            if let error = viewModel.errorMessage {
                messageCard(error, isError: true)
            }

            if let status = viewModel.statusMessage {
                messageCard(status, isError: false)
            }

            if viewModel.isLoading && viewModel.entries.isEmpty {
                loadingCard
            } else {
                HStack(alignment: .top, spacing: 24) {
                    fileList
                        .frame(maxWidth: .infinity, maxHeight: 640)
                        .focusSection()

                    detailPanel
                        .frame(width: 420)
                        .focusSection()
                }
            }
        }
    }

    private var pathCard: some View {
        HStack(spacing: 18) {
            Image(systemName: "folder")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.absolutePath ?? viewModel.root ?? "Download root")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text("\(viewModel.entries.count) item\(viewModel.entries.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.68))
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
        .padding(22)
        .background(AppCardBackground())
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.entries.isEmpty {
                emptyFolderCard
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.entries) { entry in
                            Button {
                                viewModel.select(entry)
                                focusDetailPane(for: entry)
                            } label: {
                                FileEntryRow(
                                    entry: entry,
                                    isSelected: viewModel.selectedEntry?.id == entry.id
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isWorking)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let entry = viewModel.selectedEntry {
                selectedEntryDetails(entry)
            } else {
                currentFolderDetails
            }
        }
        .padding(24)
        .background(AppCardBackground())
    }

    private var currentFolderDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            Text("Current Folder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text(viewModel.pathDisplayName)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(4)

            if viewModel.canGoUp {
                Button {
                    Task {
                        await viewModel.goUp()
                    }
                } label: {
                    Label("Open Parent", systemImage: "chevron.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedDetailTarget, equals: .parent)
            }

            Button {
                viewModel.clearMessages()
                newFolderName = ""
                isCreatingFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .focused($focusedDetailTarget, equals: .createFolder)
            .disabled(viewModel.isLoading || viewModel.isWorking)
        }
    }

    private func selectedEntryDetails(_ entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(4)

                detailRow(title: "Path", value: entry.relativePath)
                detailRow(title: "Size", value: entry.formattedSize)
                detailRow(title: "Modified", value: entry.formattedModifiedAt)
            }

            VStack(spacing: 12) {
                if entry.isDirectory {
                    Button {
                        Task {
                            await viewModel.openFolder(entry)
                        }
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .focused($focusedDetailTarget, equals: .open)
                    .disabled(viewModel.isLoading || viewModel.isWorking)
                }

                Button {
                    viewModel.clearMessages()
                    renameEntry = entry
                    renameText = entry.name
                } label: {
                    Label("Rename", systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedDetailTarget, equals: .rename)
                .disabled(viewModel.isWorking)

                Button {
                    viewModel.clearMessages()
                    moveEntry = entry
                    moveDestination = ""
                } label: {
                    Label("Move", systemImage: "folder.badge.arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedDetailTarget, equals: .move)
                .disabled(viewModel.isWorking)

                Button(role: .destructive) {
                    viewModel.clearMessages()
                    deleteEntry = entry
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedDetailTarget, equals: .delete)
                .disabled(viewModel.isWorking)
            }

            if viewModel.isWorking {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Working...")
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
        }
    }

    private var disconnectedCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Not Connected", systemImage: "network.slash")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Connect to the LAN server before browsing files.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.76))

            NavigationLink {
                ConnectionView(connectionModel: connectionModel)
            } label: {
                Label("Connection", systemImage: "network")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .background(AppCardBackground())
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Loading files...")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(AppCardBackground())
    }

    private var emptyFolderCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Text("This folder is empty")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .background(AppCardBackground())
    }

    private func messageCard(_ message: String, isError: Bool) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(isError ? Color(red: 1.0, green: 0.82, blue: 0.80) : .green)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppCardBackground())
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.48))

            Text(value)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var modalOverlay: some View {
        if isCreatingFolder {
            modalBackground {
                createFolderPanel
            }
        } else if let renameEntry {
            modalBackground {
                renamePanel(entry: renameEntry)
            }
        } else if let moveEntry {
            modalBackground {
                movePanel(entry: moveEntry)
            }
        } else if let deleteEntry {
            modalBackground {
                deletePanel(entry: deleteEntry)
            }
        }
    }

    private var createFolderPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("New Folder")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(viewModel.pathDisplayName)
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(2)

            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(18)
                .background(fieldBackground)
                .focused($focusedModalTarget, equals: .createFolderName)

            modalError

            HStack(spacing: 16) {
                Button {
                    dismissCreateFolder()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedModalTarget, equals: .createFolderCancel)

                Button {
                    Task {
                        await viewModel.createFolder(name: newFolderName)
                        if viewModel.errorMessage == nil {
                            dismissCreateFolder()
                        } else {
                            focusModal(.createFolderName)
                        }
                    }
                } label: {
                    Label(viewModel.isWorking ? "Creating..." : "Create", systemImage: "folder.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .focused($focusedModalTarget, equals: .createFolderConfirm)
                .disabled(viewModel.isWorking || newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func modalBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()

            content()
                .frame(width: 760)
                .padding(30)
                .background(AppCardBackground())
                .focusSection()
        }
    }

    private func renamePanel(entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Rename")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(entry.relativePath)
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(2)

            TextField("New name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(18)
                .background(fieldBackground)
                .focused($focusedModalTarget, equals: .renameName)

            modalError

            HStack(spacing: 16) {
                Button {
                    dismissRename()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedModalTarget, equals: .renameCancel)

                Button {
                    Task {
                        await viewModel.rename(entry, name: renameText)
                        if viewModel.errorMessage == nil {
                            dismissRename()
                        } else {
                            focusModal(.renameName)
                        }
                    }
                } label: {
                    Label(viewModel.isWorking ? "Renaming..." : "Rename", systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .focused($focusedModalTarget, equals: .renameConfirm)
                .disabled(viewModel.isWorking || renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func movePanel(entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Move")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(entry.relativePath)
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(2)

            TextField("Destination folder path", text: $moveDestination)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(18)
                .background(fieldBackground)
                .focused($focusedModalTarget, equals: .moveDestination)

            modalError

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.destinationChoices(for: entry)) { choice in
                        Button {
                            moveDestination = choice.path
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(choice.name)
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text(choice.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.66))
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .frame(width: 230, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 16) {
                Button {
                    dismissMove()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedModalTarget, equals: .moveCancel)

                Button {
                    Task {
                        await viewModel.move(entry, destination: moveDestination)
                        if viewModel.errorMessage == nil {
                            dismissMove()
                        } else {
                            focusModal(.moveDestination)
                        }
                    }
                } label: {
                    Label(viewModel.isWorking ? "Moving..." : "Move", systemImage: "folder.badge.arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .focused($focusedModalTarget, equals: .moveConfirm)
                .disabled(viewModel.isWorking)
            }
        }
    }

    private func deletePanel(entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Delete")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(entry.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text(entry.isDirectory ? "This folder and everything inside it will be deleted." : "This file will be deleted.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.76))

            modalError

            HStack(spacing: 16) {
                Button {
                    dismissDelete()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedModalTarget, equals: .deleteCancel)

                Button(role: .destructive) {
                    Task {
                        await viewModel.delete(entry)
                        if viewModel.errorMessage == nil {
                            dismissDelete()
                        } else {
                            focusModal(.deleteCancel)
                        }
                    }
                } label: {
                    Label(viewModel.isWorking ? "Deleting..." : "Delete", systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .focused($focusedModalTarget, equals: .deleteConfirm)
                .disabled(viewModel.isWorking)
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.white.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var modalError: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .font(.callout)
                .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
        }
    }

    private func configureAndLoadIfNeeded(forceReload: Bool = false) async {
        guard connectionModel.isConnected,
              let baseURL = connectionModel.resolvedAPIBaseURL else {
            return
        }

        viewModel.configure(baseURL: baseURL)

        if forceReload || !viewModel.hasLoaded {
            await viewModel.loadRoot()
        }
    }

    private func focusDetailPane(for entry: FileEntry) {
        focusedDetailTarget = nil
        DispatchQueue.main.async {
            focusedDetailTarget = entry.isDirectory ? .open : .rename
        }
    }

    private func focusModal(_ target: ModalFocusTarget) {
        focusedDetailTarget = nil
        focusedModalTarget = nil
        DispatchQueue.main.async {
            focusedModalTarget = target
        }
    }

    private func dismissRename() {
        renameEntry = nil
        renameText = ""
        focusedModalTarget = nil
    }

    private func dismissCreateFolder() {
        isCreatingFolder = false
        newFolderName = ""
        focusedModalTarget = nil
    }

    private func dismissMove() {
        moveEntry = nil
        moveDestination = ""
        focusedModalTarget = nil
    }

    private func dismissDelete() {
        deleteEntry = nil
        focusedModalTarget = nil
    }
}

private struct FileEntryRow: View {
    let entry: FileEntry
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.80))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 7) {
                Text(entry.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 16) {
                    label(icon: entry.isDirectory ? "folder" : "doc", text: entry.formattedSize)
                    label(icon: "clock", text: entry.formattedModifiedAt)
                }
            }

            Spacer(minLength: 12)

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.44))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(borderColor, lineWidth: isFocused || isSelected ? 2 : 1)
                }
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var backgroundColor: Color {
        if isFocused {
            return Color(red: 0.18, green: 0.32, blue: 0.48)
        }
        if isSelected {
            return Color.white.opacity(0.16)
        }
        return Color.white.opacity(0.08)
    }

    private var borderColor: Color {
        if isFocused || isSelected {
            return .white.opacity(0.28)
        }
        return .white.opacity(0.10)
    }

    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.50))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
        }
    }
}
