import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Servers", systemImage: "server.rack") }
            InstallerView().tabItem { Label("Install", systemImage: "plus.app") }
            ServerFilesView().tabItem { Label("Files", systemImage: "folder") }
            SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(.green)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: ServerStore
    @StateObject private var runtime = ServerRuntimeController()
    @State private var consoleCommand = ""
    @AppStorage("serverPort") private var serverPort = "25565"
    @AppStorage("bedrockPort") private var bedrockPort = "19132"
    @AppStorage("serverRAM") private var ram = DeviceMemoryPolicy.recommendedAllocationMB
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
                            VStack(spacing: 8) {
                                Image(systemName: "server.rack").font(.largeTitle).foregroundStyle(.secondary)
                                Text("No servers installed").font(.headline)
                                Text("Open Install to download a supported server.").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
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
                            Label(runtime.isRunning ? "Server running" : "Server stopped", systemImage: runtime.isRunning ? "play.circle.fill" : "stop.circle")
                                .font(.subheadline).foregroundStyle(runtime.isRunning ? .green : .secondary)
                            if let java = server.javaVersion {
                                Label("Requires Java \(java)", systemImage: "cup.and.saucer").font(.subheadline)
                            }
                            if server.edition == Edition.bedrock.rawValue {
                                Button {
                                    runtime.configureBedrock(profile: server, port: bedrockPort, maxPlayers: Int(maxPlayers))
                                } label: {
                                    Label("Save Bedrock Settings", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                Text("Bedrock uses UDP port 19132 by default. Its official server binary is Linux-only, so this saves configuration for a compatible Linux host rather than starting it on iPad.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                HStack {
                                    Button {
                                        runtime.error = nil
                                        runtime.start(profile: server, heapMB: ram, onlineMode: onlineMode, maxPlayers: Int(maxPlayers), port: serverPort)
                                    } label: { Label("Start", systemImage: "play.fill") }
                                    .buttonStyle(.borderedProminent).tint(.green).disabled(runtime.isRunning)
                                    Button { runtime.sendCommand("stop") } label: { Label("Stop", systemImage: "stop.fill") }
                                    .buttonStyle(.bordered).disabled(!runtime.isRunning)
                                }
                            }
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("PLAYERS").font(.caption2.bold()).foregroundStyle(.secondary)
                                    Text("\(runtime.onlinePlayers)/\(runtime.maximumPlayers)").font(.title3.bold().monospacedDigit())
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("RAM USAGE").font(.caption2.bold()).foregroundStyle(.secondary)
                                    Text("\(runtime.memoryUsageMB) MB").font(.title3.bold().monospacedDigit())
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("LOCAL IP").font(.caption2.bold()).foregroundStyle(.secondary)
                                    Text(runtime.localIPAddress).font(.subheadline.bold().monospaced()).lineLimit(1).minimumScaleFactor(0.75)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("PORT").font(.caption2.bold()).foregroundStyle(.secondary)
                                    Text(server.edition == Edition.bedrock.rawValue ? bedrockPort : serverPort).font(.title3.bold().monospacedDigit())
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12).background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                            if server.edition != Edition.bedrock.rawValue {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("CONSOLE").font(.caption.bold()).foregroundStyle(.secondary)
                                    HStack {
                                        TextField("Enter server command", text: $consoleCommand)
                                            .textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                                            .onSubmit { runtime.sendCommand(consoleCommand); consoleCommand = "" }
                                        Button("Send") { runtime.sendCommand(consoleCommand); consoleCommand = "" }
                                            .disabled(!runtime.isRunning || consoleCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 3) {
                                            ForEach(Array(runtime.output.suffix(250).enumerated()), id: \.offset) { _, line in
                                                Text(line).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                            }
                                        }
                                    }
                                    .frame(height: 180).padding(8).background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            if let error = runtime.error {
                                Text(error).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("DEFAULT SETTINGS").font(.caption.bold()).foregroundStyle(.secondary)
                        TextField(server?.edition == Edition.bedrock.rawValue ? "Bedrock UDP port" : "Java TCP port", text: server?.edition == Edition.bedrock.rawValue ? $bedrockPort : $serverPort)
                            .keyboardType(.numberPad)
                        Toggle("Online Mode", isOn: $onlineMode)
                        TextField("Maximum players (1–1,000,000)", value: $maxPlayers, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .onChange(of: maxPlayers) { value in
                                maxPlayers = Double(min(1_000_000, max(1, Int((value.isFinite ? value : 20).rounded()))))
                            }
                        HStack { Label("Memory allocation", systemImage: "memorychip"); Spacer(); Text("\(Int(ram)) MB / \(Int(DeviceMemoryPolicy.maximumJavaHeapMB)) MB").foregroundStyle(.secondary) }
                        Slider(value: $ram, in: 512...DeviceMemoryPolicy.maximumJavaHeapMB, step: 256)
                            .tint(.green)
                            .onChange(of: ram) { value in
                                ram = min(DeviceMemoryPolicy.maximumJavaHeapMB, max(512, value))
                            }
                        Text("Device memory: \(DeviceMemoryPolicy.physicalMemoryGB, specifier: "%.1f") GB. ServerHost reserves memory for iPadOS and other apps.")
                            .font(.caption).foregroundStyle(.secondary)
                            .onAppear {
                                ram = min(DeviceMemoryPolicy.maximumJavaHeapMB, max(512, ram))
                                maxPlayers = min(1_000_000, max(1, maxPlayers))
                            }
                    }
                    .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                }.padding()
            }
            .navigationTitle("ServerHost")
            .task {
                while !Task.isCancelled {
                    runtime.refreshStats()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
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
    @State private var downloadedBytes: Int64 = 0
    @State private var expectedBytes: Int64 = 0

    private var downloadFraction: Double {
        guard expectedBytes > 0 else { return 0 }
        return min(1, max(0, Double(downloadedBytes) / Double(expectedBytes)))
    }

    private func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }

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

                        if isInstalling {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    ProgressView()
                                    Text("Downloading server files").font(.subheadline.bold())
                                    Spacer()
                                    if expectedBytes > 0 {
                                        Text("\(Int(downloadFraction * 100))%").font(.subheadline.monospacedDigit().bold())
                                    } else {
                                        Text("Preparing").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                ProgressView(value: expectedBytes > 0 ? downloadFraction : nil)
                                    .tint(.green)
                                if expectedBytes > 0 {
                                    Text("\(megabytes(downloadedBytes)) / \(megabytes(expectedBytes)) MB")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                } else {
                                    Text("\(megabytes(downloadedBytes)) MB downloaded")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            .padding(13)
                            .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                        }
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
        downloadedBytes = 0
        expectedBytes = 0
        defer { isInstalling = false }
        do {
            let file = try await ServerInstaller.install(software: software, version: selectedVersion) { received, expected in
                downloadedBytes = received
                expectedBytes = expected
            }
            let profile = ServerProfile(software: software, version: selectedVersion, installedFile: file)
            store.add(profile)
            installMessage = "\(profile.name) downloaded and added to your server list. Open Servers to start a Java server; Bedrock Linux files need a compatible Linux host."
        } catch {
            installError = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @State private var showingRuntimeInfo = false
    @AppStorage("serverName") private var serverName = "My Minecraft Server"
    @AppStorage("serverPort") private var serverPort = "25565"
    @AppStorage("bedrockPort") private var bedrockPort = "19132"
    @AppStorage("serverRAM") private var ram = 2048.0
    @AppStorage("onlineMode") private var onlineMode = true
    @AppStorage("maxPlayers") private var maxPlayers = 20.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Network ports") {
                    TextField("Java TCP port", text: $serverPort).keyboardType(.numberPad)
                    TextField("Bedrock UDP port", text: $bedrockPort).keyboardType(.numberPad)
                    Text("Java defaults to 25565/TCP. Bedrock defaults to 19132/UDP. The Bedrock value is saved into its server.properties file.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Server defaults") {
                    TextField("Server name", text: $serverName)
                    Toggle("Online Mode", isOn: $onlineMode)
                }
                Section("Resources") {
                    HStack { Text("RAM allocation"); Spacer(); Text("\(Int(ram)) MB").foregroundStyle(.secondary) }
                    Slider(value: $ram, in: 512...DeviceMemoryPolicy.maximumJavaHeapMB, step: 256)
                        .onChange(of: ram) { value in
                            ram = min(DeviceMemoryPolicy.maximumJavaHeapMB, max(512, value))
                        }
                    Text("Device: \(DeviceMemoryPolicy.physicalMemoryGB, specifier: "%.1f") GB · Safe heap limit: \(Int(DeviceMemoryPolicy.maximumJavaHeapMB)) MB")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Maximum players (1–1,000,000)", value: $maxPlayers, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .onChange(of: maxPlayers) { value in
                            maxPlayers = Double(min(1_000_000, max(1, Int((value.isFinite ? value : 20).rounded()))))
                        }
                }
                Section("Java runtimes") {
                    ForEach([8, 17, 21, 25], id: \.self) { version in
                        HStack {
                            Text("Java \(version)")
                            Spacer()
                            Text("Bundled by build").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("ServerHost packages Amethyst-compatible iOS ARM64 Java runtimes for Java 8, 17, 21 and 25. The native JLI launcher starts Java server JARs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Hosting status") {
                    Label("Java local hosting · Bedrock Linux-only", systemImage: "server.rack")
                    Text("Java server JARs use the bundled iOS ARM64 runtime. JIT support is required for useful performance. The official Bedrock Dedicated Server is a Linux executable and must be run on a compatible Linux host.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("RAM, Online Mode, player limit and port are written to server.properties when a Java server starts. Minecraft requires eula=true in eula.txt; review the EULA with a parent or guardian before enabling it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    HStack { Text("Version"); Spacer(); Text("0.2.0").foregroundStyle(.secondary) }
                }
            }
            .onAppear {
                ram = DeviceMemoryPolicy.clampedAllocation(ram)
                maxPlayers = Double(DeviceMemoryPolicy.clampedPlayerCount(maxPlayers))
            }
            .navigationTitle("Settings")
            .alert("Java runtime cannot run locally", isPresented: $showingRuntimeInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The iOS ARM64 Java runtime integration is not installed yet. These device-limited settings will be applied when the Java server launcher is connected.")
            }
        }
    }
}
