import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Servers", systemImage: "server.rack") }
            InstallerView().tabItem { Label("Install", systemImage: "plus.app") }
            SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(.green)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: ServerStore
    @AppStorage("serverRAM") private var ram = 2048.0
    @AppStorage("onlineMode") private var onlineMode = true
    @AppStorage("maxPlayers") private var maxPlayers = 20.0
    @State private var profileToDelete: ServerProfile?
    @State private var showingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SAVED SERVERS").font(.caption.bold()).foregroundStyle(.secondary)
                        if store.servers.isEmpty {
                            ContentUnavailableView("No servers installed", systemImage: "server.rack", description: Text("Open Install to download a supported server."))
                        } else {
                            ForEach(store.servers) { server in
                                Button { store.selectedServerID = server.id } label: {
                                    HStack {
                                        Image(systemName: server.edition == "Java" ? "cup.and.saucer.fill" : "cube.fill").foregroundStyle(.green)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(server.name).font(.headline)
                                            Text("\(server.softwareName) · \(server.version)").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if store.selectedServerID == server.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                    }
                                    .padding(11)
                                    .background(store.selectedServerID == server.id ? .green.opacity(0.13) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete server", role: .destructive) {
                                        profileToDelete = server
                                        showingDelete = true
                                    }
                                }
                            }
                        }
                    }
                    .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

                    if let server = store.selectedServer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SELECTED SERVER").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(server.name).font(.title2.bold())
                            Label("Files installed · Not running", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.green)
                            Text("The server files are saved in this app. Starting server processes is not available on iOS yet.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let java = server.javaVersion {
                                Label("Requires Java \(java)", systemImage: "cup.and.saucer").font(.subheadline)
                            }
                        }
                        .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("DEFAULT SETTINGS").font(.caption.bold()).foregroundStyle(.secondary)
                        Toggle("Online Mode", isOn: $onlineMode)
                        HStack { Label("Maximum players", systemImage: "person.3"); Spacer(); Text("\(Int(maxPlayers))").foregroundStyle(.secondary) }
                        Slider(value: $maxPlayers, in: 1...100, step: 1).tint(.green)
                        HStack { Label("Memory allocation", systemImage: "memorychip"); Spacer(); Text("\(Int(ram)) MB").foregroundStyle(.secondary) }
                        Slider(value: $ram, in: 512...8192, step: 256).tint(.green)
                    }
                    .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                }.padding()
            }
            .navigationTitle("ServerHost")
            .alert("Delete saved server?", isPresented: $showingDelete, presenting: profileToDelete) { server in
                Button("Delete", role: .destructive) { store.remove(server) }
                Button("Cancel", role: .cancel) {}
            } message: { server in
                Text("This removes the profile from the list. Downloaded files remain in app storage.")
            }
        }
    }
}

struct InstallerView: View {
    @EnvironmentObject private var store: ServerStore
    @State private var edition: Edition = .java
    @State private var selectedSoftware: ServerSoftware?
    @State private var search = ""
    @State private var selectedVersion = ""
    @StateObject private var catalog = VersionCatalog()
    @State private var isInstalling = false
    @State private var installMessage: String?
    @State private var installError: String?

    private var software: [ServerSoftware] { ServerSoftware.all.filter { $0.edition == edition } }
    private var filteredVersions: [String] {
        catalog.versions.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Edition", selection: $edition) {
                        ForEach(Edition.allCases) { item in Text(item.rawValue).tag(item) }
                    }.pickerStyle(.segmented)

                    Text("Choose server software").font(.title2.bold())
                    ForEach(software) { item in
                        Button {
                            selectedSoftware = item
                            selectedVersion = ""
                            search = ""
                            Task { await catalog.load(for: item) }
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: item.edition == .java ? "cup.and.saucer.fill" : "cube.fill")
                                    .font(.title2).foregroundStyle(.green).frame(width: 42, height: 42)
                                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.name).font(.headline)
                                        Spacer()
                                        Text(item.category.uppercased()).font(.caption2.bold()).foregroundStyle(.green)
                                    }
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Image(systemName: selectedSoftware?.id == item.id ? "checkmark.circle.fill" : "chevron.right")
                                    .foregroundStyle(selectedSoftware?.id == item.id ? .green : .secondary)
                            }
                            .padding(12)
                            .background(selectedSoftware?.id == item.id ? .green.opacity(0.12) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }

                    if let selectedSoftware {
                        Divider().padding(.vertical, 3)
                        Text("Choose version").font(.title2.bold())
                        Text(selectedSoftware.name + " · " + selectedSoftware.source).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search versions...", text: $search).autocorrectionDisabled()
                        }
                        .padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

                        if catalog.isLoading {
                            ProgressView("Loading versions...")
                        } else {
                            if let error = catalog.error { Text(error).font(.caption).foregroundStyle(.orange) }
                            ScrollView(.vertical) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                    ForEach(filteredVersions, id: \.self) { version in
                                        Button { selectedVersion = version } label: {
                                            Text(version).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 11)
                                                .background(selectedVersion == version ? .green : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                                .foregroundStyle(selectedVersion == version ? .black : .white)
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.vertical, 2)
                            }
                            .frame(height: 156)
                            .scrollIndicators(.visible)
                            Text("\(filteredVersions.count) versions · scroll inside to see more").font(.caption2).foregroundStyle(.secondary)
                        }

                        if selectedSoftware.edition == .java && !selectedVersion.isEmpty {
                            let java = JavaCompatibility.required(for: selectedVersion)
                            Label("This version needs Java \(java)", systemImage: "cpu").font(.subheadline).foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await installSelected(selectedSoftware) }
                        } label: {
                            if isInstalling {
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 14)
                            } else {
                                Label("Install \(selectedSoftware.name)", systemImage: "arrow.down.circle.fill")
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(.green)
                        .disabled(selectedVersion.isEmpty || catalog.isLoading || isInstalling)
                    }
                }.padding()
            }
            .navigationTitle("Server Installer")
            .alert(installError == nil ? "Server installed" : "Installation failed", isPresented: Binding(
                get: { installMessage != nil || installError != nil },
                set: { if !$0 { installMessage = nil; installError = nil } }
            )) {
                Button("OK", role: .cancel) { installMessage = nil; installError = nil }
            } message: {
                Text(installError ?? installMessage ?? "")
            }
        }
    }

    @MainActor
    private func installSelected(_ software: ServerSoftware) async {
        isInstalling = true
        defer { isInstalling = false }
        do {
            let file = try await ServerInstaller.install(software: software, version: selectedVersion)
            let profile = ServerProfile(software: software, version: selectedVersion, installedFile: file)
            store.add(profile)
            installMessage = "\(profile.name) downloaded and added to your server list. Starting it is not available on iOS yet."
        } catch {
            installError = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @AppStorage("serverName") private var serverName = "My Minecraft Server"
    @AppStorage("serverPort") private var serverPort = "25565"
    @AppStorage("serverRAM") private var ram = 2048.0
    @AppStorage("onlineMode") private var onlineMode = true
    @AppStorage("maxPlayers") private var maxPlayers = 20.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Server defaults") {
                    TextField("Server name", text: $serverName)
                    TextField("Port", text: $serverPort).keyboardType(.numberPad)
                    Toggle("Online Mode", isOn: $onlineMode)
                }
                Section("Resources") {
                    HStack { Text("RAM"); Spacer(); Text("\(Int(ram)) MB").foregroundStyle(.secondary) }
                    Slider(value: $ram, in: 512...8192, step: 256)
                    HStack { Text("Max players"); Spacer(); Text("\(Int(maxPlayers))").foregroundStyle(.secondary) }
                    Slider(value: $maxPlayers, in: 1...100, step: 1)
                }
                Section("Java runtimes") {
                    ForEach([8, 17, 21, 25], id: \.self) { version in
                        HStack {
                            Text("Java \(version)")
                            Spacer()
                            Text("iOS runtime unavailable").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("ServerHost detects the required Java version. Desktop and Linux Java packages cannot be installed as iOS runtimes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Background hosting") {
                    Label("iOS may suspend apps in the background.", systemImage: "moon.zzz")
                    Text("This build downloads supported server files and manages multiple profiles. Running server processes and reliable 24/7 hosting need a compatible runtime host.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    HStack { Text("Version"); Spacer(); Text("0.2.0").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
