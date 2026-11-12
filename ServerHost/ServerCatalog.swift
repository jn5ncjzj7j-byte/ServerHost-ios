import Foundation
import Combine

enum Edition: String, CaseIterable, Identifiable {
    case java = "Java"
    case bedrock = "Bedrock"
    var id: String { rawValue }
}

struct ServerSoftware: Identifiable, Hashable {
    let id: String
    let name: String
    let edition: Edition
    let detail: String
    let category: String
    let versions: [String]
    let source: String

    static let all: [ServerSoftware] = [
        .init(id: "vanilla", name: "Vanilla", edition: .java, detail: "Official Minecraft Java server", category: "Official", versions: ["26.3", "26.2", "26.1", "1.21.11", "1.21.10", "1.21.9", "1.21.8", "1.21.7", "1.21.6", "1.21.5", "1.21.4", "1.21.1", "1.20.4", "1.20.1", "1.19.4", "1.18.2", "1.16.5"], source: "Mojang"),
        .init(id: "paper", name: "Paper", edition: .java, detail: "High-performance plugin server", category: "Plugins", versions: ["1.21.11", "1.21.10", "1.21.9", "1.21.8", "1.21.7", "1.21.6", "1.21.5", "1.21.4", "1.21.1", "1.20.4", "1.20.1"], source: "PaperMC"),
        .init(id: "purpur", name: "Purpur", edition: .java, detail: "Configurable Paper fork", category: "Plugins", versions: ["1.21.11", "1.21.10", "1.21.8", "1.21.5", "1.21.4", "1.21.1", "1.20.4", "1.20.1"], source: "Purpur"),
        .init(id: "fabric", name: "Fabric", edition: .java, detail: "Lightweight mod loader", category: "Mods", versions: ["1.21.11", "1.21.10", "1.21.8", "1.21.5", "1.21.4", "1.21.1", "1.20.4", "1.20.1"], source: "Fabric"),
        .init(id: "forge", name: "Forge", edition: .java, detail: "Classic Java mod loader", category: "Mods", versions: ["1.21.1", "1.20.1", "1.19.2", "1.18.2", "1.16.5", "1.12.2"], source: "Forge"),
        .init(id: "neoforge", name: "NeoForge", edition: .java, detail: "Modern Java mod loader", category: "Mods", versions: ["1.21.1", "1.21.4", "1.21.5", "1.21.8", "1.21.10"], source: "NeoForged"),
        .init(id: "quilt", name: "Quilt", edition: .java, detail: "Community mod loader", category: "Mods", versions: ["1.21.1", "1.20.4", "1.20.1", "1.19.2"], source: "Quilt"),
        .init(id: "bedrock", name: "Bedrock Dedicated Server", edition: .bedrock, detail: "Official Bedrock server · stable releases", category: "Official", versions: BedrockVersionCatalog.versions, source: "Mojang"),
        .init(id: "pocketmine", name: "PocketMine-MP", edition: .bedrock, detail: "Bedrock server with plugins", category: "Plugins", versions: ["Latest release"], source: "GitHub Releases"),
        .init(id: "nukkit", name: "Nukkit", edition: .bedrock, detail: "Extensible Bedrock server", category: "Plugins", versions: ["Latest release"], source: "GitHub Releases"),
        .init(id: "powernukkitx", name: "PowerNukkitX", edition: .bedrock, detail: "Modern Nukkit-based server", category: "Plugins", versions: ["Latest release"], source: "GitHub Releases")
    ]
}

@MainActor
final class VersionCatalog: ObservableObject {
    @Published var versions: [String] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(for software: ServerSoftware) async {
        isLoading = true
        error = nil
        var found = software.versions
        do {
            switch software.id {
            case "vanilla":
                let url = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
                let data = try await URLSession.shared.data(from: url).0
                let manifest = try JSONDecoder().decode(MojangManifest.self, from: data)
                found = manifest.versions.filter { $0.type == "release" }.map(\.id)
            case "paper":
                let url = URL(string: "https://api.papermc.io/v2/projects/paper")!
                let data = try await URLSession.shared.data(from: url).0
                let result = try JSONDecoder().decode(ProjectVersions.self, from: data)
                found = Array(result.versions.reversed())
            case "fabric":
                let url = URL(string: "https://meta.fabricmc.net/v2/versions/game")!
                let data = try await URLSession.shared.data(from: url).0
                let result = try JSONDecoder().decode([FabricVersion].self, from: data)
                found = result.filter { $0.stable }.map(\.version)
            case "bedrock":
                found = BedrockVersionCatalog.versions
            case "pocketmine":
                found = try await githubReleases("pmmp/PocketMine-MP")
            case "nukkit":
                found = try await githubReleases("CloudburstMC/Nukkit")
            case "powernukkitx":
                found = try await githubReleases("PowerNukkitX/PowerNukkitX")
            default:
                break
            }
        } catch {
            self.error = "Couldn't refresh this source. Showing fallback versions."
        }
        versions = found
        isLoading = false
    }

    private func githubReleases(_ repository: String) async throws -> [String] {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")!
        var request = URLRequest(url: url)
        request.setValue("ServerHost-iOS", forHTTPHeaderField: "User-Agent")
        let data = try await URLSession.shared.data(for: request).0
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        let tags = releases.map(\.tag_name)
        return tags.isEmpty ? ["Latest release"] : tags
    }
}

private struct MojangManifest: Decodable { let versions: [MojangVersion] }
private struct MojangVersion: Decodable { let id: String; let type: String }
private struct ProjectVersions: Decodable { let versions: [String] }
private struct FabricVersion: Decodable { let version: String; let stable: Bool }
private struct GitHubRelease: Decodable { let tag_name: String }


enum BedrockVersionCatalog {
    static let versions = [
        "1.26.52.3", "1.26.3.1", "1.26.2.1", "1.26.1.1", "1.26.0.2",
        "1.21.132.3", "1.21.131.1", "1.21.130.4", "1.21.124.2", "1.21.123.1",
        "1.21.120.4", "1.21.114.1", "1.21.111.1", "1.21.101.1", "1.21.93.1",
        "1.21.90.3", "1.21.80.3", "1.21.70.3", "1.21.62.1", "1.21.60.10",
        "1.21.51.2", "1.21.50.10", "1.21.44.1", "1.21.42.1", "1.21.30.3",
        "1.21.2.2", "1.21.0.3", "1.20.81.1", "1.20.80.5", "1.20.73.1",
        "1.20.72.1", "1.20.62.2", "1.20.51.1", "1.20.41.2", "1.20.32.3",
        "1.20.15.1", "1.20.10.1", "1.20.1.2", "1.19.83.1", "1.19.81.1"
    ]
}
