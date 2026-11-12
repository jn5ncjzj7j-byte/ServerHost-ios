import SwiftUI
import UniformTypeIdentifiers

struct ServerFilesView: View {
    @EnvironmentObject private var store: ServerStore
    @State private var files: [URL] = []
    @State private var selectedFile: URL?
    @State private var editorText = ""
    @State private var showingImporter = false
    @State private var showingEditor = false
    @State private var showingDelete = false
    @State private var fileToDelete: URL?
    @State private var errorMessage: String?

    private var serverFolder: URL? {
        guard let server = store.selectedServer else { return nil }
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Servers", isDirectory: true)
        return root.appendingPathComponent(server.installedFile.components(separatedBy: "/").first ?? "", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let server = store.selectedServer, let folder = serverFolder {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name).font(.headline)
                                Text(folder.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                showingImporter = true
                            } label: {
                                Label("Add", systemImage: "plus").font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        .padding()

                        if files.isEmpty {
                            ContentUnavailableView("No files found", systemImage: "folder", description: Text("Add files or install a server first."))
                        } else {
                            List {
                                ForEach(files, id: \.path) { file in
                                    Button {
                                        open(file)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: icon(for: file)).foregroundStyle(.green).frame(width: 24)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(file.lastPathComponent).foregroundStyle(.primary)
                                                Text(relativePath(file, from: folder)).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if isEditable(file) {
                                                Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .contextMenu {
                                        Button("Edit") { open(file) }
                                        Button("Delete", role: .destructive) {
                                            fileToDelete = file
                                            showingDelete = true
                                        }
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                        }
                    }
                    .onAppear { refresh() }
                    .onChange(of: store.selectedServerID) { _ in refresh() }
                    .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                        importFiles(result, into: folder)
                    }
                    .alert("Delete file?", isPresented: $showingDelete, presenting: fileToDelete) { file in
                        Button("Delete", role: .destructive) {
                            do {
                                try FileManager.default.removeItem(at: file)
                                refresh()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: { file in
                        Text("Delete \(file.lastPathComponent)?")
                    }
                    .alert("Files error", isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    )) {
                        Button("OK", role: .cancel) { errorMessage = nil }
                    } message: {
                        Text(errorMessage ?? "")
                    }
                    .sheet(isPresented: $showingEditor) {
                        NavigationStack {
                            TextEditor(text: $editorText)
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                                .navigationTitle(selectedFile?.lastPathComponent ?? "Edit file")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Cancel") { showingEditor = false }
                                    }
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Save") { saveEditor() }
                                    }
                                }
                        }
                    }
                } else {
                    ContentUnavailableView("Select a server", systemImage: "server.rack", description: Text("Install or select a server to manage its files."))
                }
            }
            .navigationTitle("Files")
        }
    }

    private func refresh() {
        guard let folder = serverFolder else {
            files = []
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            files = (enumerator?.allObjects as? [URL] ?? []).filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
            }.sorted { relativePath($0, from: folder).localizedStandardCompare(relativePath($1, from: folder)) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ url: URL) {
        guard isEditable(url) else {
            errorMessage = "This file type is not a text configuration file."
            return
        }
        do {
            editorText = try String(contentsOf: url, encoding: .utf8)
            selectedFile = url
            showingEditor = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveEditor() {
        guard let selectedFile else { return }
        do {
            try editorText.write(to: selectedFile, atomically: true, encoding: .utf8)
            showingEditor = false
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFiles(_ result: Result<[URL], Error>, into folder: URL) {
        do {
            for source in try result.get() {
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                var destination = folder.appendingPathComponent(source.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    let name = source.deletingPathExtension().lastPathComponent
                    let ext = source.pathExtension
                    destination = folder.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8))").appendingPathExtension(ext)
                }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isEditable(_ url: URL) -> Bool {
        ["txt", "properties", "json", "yml", "yaml", "toml", "cfg", "conf", "ini", "log", "md"].contains(url.pathExtension.lowercased())
    }

    private func icon(for url: URL) -> String {
        isEditable(url) ? "doc.text" : "doc"
    }

    private func relativePath(_ url: URL, from folder: URL) -> String {
        let prefix = folder.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.lastPathComponent
    }
}
