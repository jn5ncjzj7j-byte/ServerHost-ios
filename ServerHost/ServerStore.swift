import Foundation
import Combine

struct ServerProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var softwareID: String
    var softwareName: String
    var edition: String
    var version: String
    var installedFile: String
    var javaVersion: Int?

    init(software: ServerSoftware, version: String, installedFile: String) {
        id = UUID()
        name = "\(software.name) \(version)"
        softwareID = software.id
        softwareName = software.name
        edition = software.edition.rawValue
        self.version = version
        self.installedFile = installedFile
        javaVersion = software.edition == .java ? JavaCompatibility.required(for: version) : nil
    }
}

@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [ServerProfile] = []
    @Published var selectedServerID: UUID?
    private let key = "savedServerProfiles"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            servers = saved
        }
        selectedServerID = servers.first?.id
    }

    var selectedServer: ServerProfile? { servers.first { $0.id == selectedServerID } }

    func add(_ profile: ServerProfile) {
        servers.insert(profile, at: 0)
        selectedServerID = profile.id
        save()
    }

    func remove(_ profile: ServerProfile) {
        servers.removeAll { $0.id == profile.id }
        if selectedServerID == profile.id { selectedServerID = servers.first?.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum JavaCompatibility {
    static func required(for version: String) -> Int {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { return 21 }
        if major >= 26 { return 25 }
        if major >= 21 { return 21 }
        if major >= 18 { return 17 }
        return 8
    }
}

enum ServerInstallError: LocalizedError {
    case unsupported
    case invalidResponse
    case missingDownload

    var errorDescription: String? {
        switch self {
        case .unsupported: return "A working installer is not available for this server type yet."
        case .invalidResponse: return "The download source returned an invalid response."
        case .missingDownload: return "No compatible server download was found."
        }
    }
}

enum ServerInstaller {
    static func install(software: ServerSoftware, version: String) async throws -> String {
        let source: URL
        switch software.id {
        case "vanilla": source = try await vanillaURL(version)
        case "paper": source = try await paperURL(version)
        case "pocketmine": source = try await pocketMineURL()
        default: throw ServerInstallError.unsupported
        }

        let (temporary, response) = try await URLSession.shared.download(from: source)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServerInstallError.invalidResponse }

        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Servers", isDirectory: true)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = source.lastPathComponent.isEmpty ? (software.id == "pocketmine" ? "PocketMine-MP.phar" : "server.jar") : source.lastPathComponent
        try FileManager.default.moveItem(at: temporary, to: folder.appendingPathComponent(name))
        return name
    }

    private static func vanillaURL(_ version: String) async throws -> URL {
        let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
        let data = try await URLSession.shared.data(from: manifestURL).0
        let manifest = try JSONDecoder().decode(MojangManifest.self, from: data)
        guard let item = manifest.versions.first(where: { $0.id == version }) else { throw ServerInstallError.missingDownload }
        let detailData = try await URLSession.shared.data(from: item.url).0
        let details = try JSONDecoder().decode(MojangVersionDetails.self, from: detailData)
        guard let address = details.downloads.server?.url, let url = URL(string: address) else { throw ServerInstallError.missingDownload }
        return url
    }

    private static func paperURL(_ version: String) async throws -> URL {
        let endpoint = URL(string: "https://api.papermc.io/v2/projects/paper/versions/\(version)/builds")!
        let data = try await URLSession.shared.data(from: endpoint).0
        let result = try JSONDecoder().decode(PaperBuilds.self, from: data)
        guard let build = result.builds.last else { throw ServerInstallError.missingDownload }
        let address = "https://api.papermc.io/v2/projects/paper/versions/\(version)/builds/\(build.build)/downloads/\(build.downloads.application.name)"
        guard let url = URL(string: address) else { throw ServerInstallError.missingDownload }
        return url
    }

    private static func pocketMineURL() async throws -> URL {
        let endpoint = URL(string: "https://api.github.com/repos/pmmp/PocketMine-MP/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("ServerHost-iOS", forHTTPHeaderField: "User-Agent")
        let data = try await URLSession.shared.data(for: request).0
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".phar") }),
              let url = URL(string: asset.browser_download_url) else { throw ServerInstallError.missingDownload }
        return url
    }
}

private struct MojangManifest: Decodable { let versions: [MojangManifestVersion] }
private struct MojangManifestVersion: Decodable { let id: String; let url: URL }
private struct MojangVersionDetails: Decodable {
    struct Downloads: Decodable {
        struct Download: Decodable { let url: String }
        let server: Download?
    }
    let downloads: Downloads
}
private struct PaperBuilds: Decodable {
    struct Build: Decodable {
        struct Downloads: Decodable {
            struct Application: Decodable { let name: String }
            let application: Application
        }
        let build: Int
        let downloads: Downloads
    }
    let builds: [Build]
}
private struct GitHubRelease: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: String }
    let assets: [Asset]
}
