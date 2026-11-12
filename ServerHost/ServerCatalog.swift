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
        .init(id: "vanilla", name: "Vanilla", edition: .java, detail: "Official Minecraft Java server", category: "Official", versions: ["26.2", "26.1", "1.21.11", "1.21.10", "1.21.9", "1.21.8", "1.21.7", "1.21.6", "1.21.5", "1.21.4", "1.21.3", "1.21.2", "1.21.1", "1.20.6", "1.20.4", "1.20.1", "1.19.4", "1.18.2", "1.16.5"], source: "Mojang"),
        .init(id: "paper", name: "Paper", edition: .java, detail: "High-performance plugin server", category: "Plugins", versions: ["1.21.11", "1.21.10", "1.21.9", "1.21.8", "1.21.7", "1.21.6", "1.21.5", "1.21.4", "1.21.1", "1.20.6", "1.20.4", "1.20.1"], source: "PaperMC"),
        .init(id: "purpur", name: "Purpur", edition: .java, detail: "Configurable Paper fork", category: "Plugins", versions: ["1.21.11", "1.21.10", "1.21.8", "1.21.5", "1.21.4", "1.21.1", "1.20.6", "1.20.4", "1.20.1"], source: "Purpur"),
        .init(id: "fabric", name: "Fabric", edition: .java, detail: "Lightweight mod loader", category: "Mods", versions: ["1.21.11", "1.21.10", "1.21.8", "1.21.5", "1.21.4", "1.21.1", "1.20.4", "1.20.1"], source: "Fabric"),
        .init(id: "forge", name: "Forge", edition: .java, detail: "Classic Java mod loader", category: "Mods", versions: ["1.21.1", "1.20.1", "1.19.2", "1.18.2", "1.16.5", "1.12.2"], source: "Forge"),
        .init(id: "neoforge", name: "NeoForge", edition: .java, detail: "Modern mod loader", category: "Mods", versions: ["1.21.1", "1.21.4", "1.21.5", "1.21.8", "1.21.10"], source: "NeoForged"),
        .init(id: "quilt", name: "Quilt", edition: .java, detail: "Community mod loader", category: "Mods", versions: ["1.21.1", "1.20.4", "1.20.1", "1.19.2"], source: "Quilt"),
        .init(id: "bedrock", name: "Bedrock Dedicated Server", edition: .bedrock, detail: "Official Bedrock server", category: "Official", versions: ["Latest stable"], source: "Mojang"),
        .init(id: "pocketmine", name: "PocketMine-MP", edition: .bedrock, detail: "Bedrock server with plugins", category: "Plugins", versions: ["5.x", "4.x"], source: "PocketMine"),
        .init(id: "nukkit", name: "Nukkit", edition: .bedrock, detail: "Extensible Bedrock server", category: "Plugins", versions: ["Latest", "1.21"], source: "Nukkit"),
        .init(id: "powernukkitx", name: "PowerNukkitX", edition: .bedrock, detail: "Modern Nukkit-based server", category: "Plugins", versions: ["Latest", "1.21"], source: "PowerNukkitX")
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
            if software.id == "vanilla" {
                let url = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let manifest = try JSONDecoder().decode(MojangManifest.self, from: data)
                found = manifest.versions.filter { $0.type == "release" }.map(\.id)
            } else if software.id == "paper" || software.id == "purpur" {
                let url = URL(string: "https://api.papermc.io/v2/projects/\(software.id)")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(ProjectVersions.self, from: data)
                found = response.versions.reversed()
            } else if software.id == "fabric" {
                let url = URL(string: "https://meta.fabricmc.net/v2/versions/game")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode([FabricVersion].self, from: data)
                found = response.filter { $0.stable }.map(\.version)
            }
        } catch {
            self.error = "Could not refresh versions. Showing the built-in list."
        }
        versions = found
        isLoading = false
    }
}

private struct MojangManifest: Decodable { let versions: [MojangVersion] }
private struct MojangVersion: Decodable { let id: String; let type: String }
private struct ProjectVersions: Decodable { let versions: [String] }
private struct FabricVersion: Decodable { let version: String; let stable: Bool }
