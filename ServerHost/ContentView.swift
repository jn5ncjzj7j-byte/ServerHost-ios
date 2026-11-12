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
    @AppStorage("serverName") private var serverName = "My Minecraft Server"
    @AppStorage("serverRAM") private var ram = 2048.0
    @AppStorage("onlineMode") private var onlineMode = true
    @AppStorage("maxPlayers") private var maxPlayers = 20.0
    @State private var showRuntimeInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SERVER CONTROL").font(.caption.bold()).foregroundStyle(.secondary)
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(serverName).font(.title2.bold())
                                Label("Not running", systemImage: "circle.fill").font(.subheadline).foregroundStyle(.orange)
                            }
                            Spacer()
                            Image(systemName: "server.rack").font(.system(size: 38)).foregroundStyle(.green)
                        }
                        HStack(spacing: 10) {
                            Button {} label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 13) }
                                .buttonStyle(.borderedProminent).tint(.green).disabled(true)
                            Button {} label: { Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 13) }
                                .buttonStyle(.bordered).disabled(true)
                        }
                        Text("Server runtime is not connected in this build.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    HStack(spacing: 12) {
                        MetricCard(title: "PLAYERS", value: "—", symbol: "person.2")
                        MetricCard(title: "MEMORY", value: "—", symbol: "memorychip")
                        MetricCard(title: "UPTIME", value: "—", symbol: "clock")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("QUICK SETTINGS").font(.caption.bold()).foregroundStyle(.secondary)
                        Toggle("Online Mode", isOn: $onlineMode)
                        HStack { Label("Maximum players", systemImage: "person.3"); Spacer(); Text("\(Int(maxPlayers))").foregroundStyle(.secondary) }
                        Slider(value: $maxPlayers, in: 1...100, step: 1).tint(.green)
                        HStack { Label("Memory allocation", systemImage: "memorychip"); Spacer(); Text("\(Int(ram)) MB").foregroundStyle(.secondary) }
                        Slider(value: $ram, in: 512...8192, step: 256).tint(.green)
                    }
                    .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    Button { showRuntimeInfo = true } label: {
                        Label("Why can't iOS run every server?", systemImage: "info.circle").font(.footnote)
                    }.foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("ServerHost")
            .alert("iOS server runtime", isPresented: $showRuntimeInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This build includes the manager interface and version discovery, not a general-purpose Java or Bedrock runtime. Arbitrary Java servers need a compatible JVM. Bedrock Linux binaries do not run as native iOS apps. iOS may suspend background work.")
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.green)
            Text(value).font(.title2.bold())
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct InstallerView: View {
    @State private var edition: Edition = .java
    @State private var selectedSoftware: ServerSoftware?
    @State private var search = ""
    @State private var selectedVersion = ""
    @StateObject private var catalog = VersionCatalog()
    @State private var showInstallInfo = false

    private var software: [ServerSoftware] { ServerSoftware.all.filter { $0.edition == edition } }
    private var filteredVersions: [String] {
        catalog.versions.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Edition", selection: $edition) {
                        ForEach(Edition.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
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
                        }
                        .buttonStyle(.plain)
                    }
                    if let selectedSoftware {
                        Divider().padding(.vertical, 4)
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
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 9) {
                                ForEach(filteredVersions, id: \.self) { version in
                                    Button { selectedVersion = version } label: {
                                        Text(version).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                                            .background(selectedVersion == version ? .green : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(selectedVersion == version ? .black : .white)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Button { showInstallInfo = true } label: {
                            Label("Prepare \(selectedSoftware.name) \(selectedVersion.isEmpty ? "server" : selectedVersion)", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent).tint(.green)
                        .disabled(selectedVersion.isEmpty || catalog.isLoading)
                    }
                }
                .padding()
            }
            .navigationTitle("Server Installer")
            .alert("Runtime not included yet", isPresented: $showInstallInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You selected \(selectedSoftware?.name ?? "server") \(selectedVersion). Version search works, but installation and server execution are not implemented in this build.")
            }
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
                Section("Server") {
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
                Section("Background hosting") {
                    Label("iOS may suspend apps in the background.", systemImage: "moon.zzz")
                    Text("Background execution is not guaranteed. Reliable 24/7 hosting requires a remote server or a supported runtime with an appropriate background strategy.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    HStack { Text("Version"); Spacer(); Text("0.1.0").foregroundStyle(.secondary) }
                    Text("Early development build. Server controls are not connected to a runtime yet.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
