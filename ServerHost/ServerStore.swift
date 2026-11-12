import Foundation
import Combine
import ZIPFoundation

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
        let release = major == 1 ? (parts.count > 1 ? parts[1] : 0) : major
        if release >= 26 { return 25 }
        if release >= 21 { return 21 }
        if release >= 20 {
            if release > 20 || parts.count > 2 && parts[2] >= 5 { return 21 }
            return 17
        }
        if release >= 17 { return 17 }
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

private final class ServerFileDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var session: URLSession?
    private let progress: (Int64, Int64) -> Void

    init(progress: @escaping (Int64, Int64) -> Void) {
        self.progress = progress
    }

    func start(url: URL, destination: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.destination = destination
            let configuration = URLSessionConfiguration.default
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            session?.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite
        Task { @MainActor in
            progress(totalBytesWritten, expected)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let destination else { throw ServerInstallError.invalidResponse }
            guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                throw ServerInstallError.invalidResponse
            }
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
        session.invalidateAndCancel()
    }
}

enum ServerInstaller {
    static func install(
        software: ServerSoftware,
        version: String,
        onProgress: @escaping (Int64, Int64) -> Void
    ) async throws -> String {
        let source: URL
        switch software.id {
        case "vanilla": source = try await vanillaURL(version)
        case "paper": source = try await paperURL(version)
        case "pocketmine": source = try await pocketMineURL(version)
        case "bedrock": source = try await bedrockURL(version)
        default: throw ServerInstallError.unsupported
        }

        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Servers", isDirectory: true)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = source.lastPathComponent.isEmpty ? (software.id == "pocketmine" ? "PocketMine-MP.phar" : "server.jar") : source.lastPathComponent
        let destination = folder.appendingPathComponent(name)
        let downloader = ServerFileDownloader(progress: onProgress)
        _ = try await downloader.start(url: source, destination: destination)

        if software.id == "bedrock" {
            let extracted = folder.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            try FileManager.default.unzipItem(at: destination, to: extracted)
            return folder.lastPathComponent + "/extracted/bedrock_server"
        }

        return folder.lastPathComponent + "/" + name
    }

    private static func bedrockURL(_ version: String) async throws -> URL {
        if version != "Latest stable" {
            guard let url = URL(string: "https://minecraft.azureedge.net/bin-linux/bedrock-server-\(version).zip") else { throw ServerInstallError.missingDownload }
            return url
        }
        let endpoint = URL(string: "https://net-secondary.web.minecraft-services.net/api/v1.0/download/links")!
        let data = try await URLSession.shared.data(from: endpoint).0
        let response = try JSONDecoder().decode(BedrockDownloadLinks.self, from: data)
        guard let address = response.result.links.first(where: { $0.downloadType == "serverBedrockLinux" })?.downloadUrl,
              let url = URL(string: address) else { throw ServerInstallError.missingDownload }
        return url
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

    private static func pocketMineURL(_ version: String) async throws -> URL {
        let endpoint = URL(string: version == "Latest release" ? "https://api.github.com/repos/pmmp/PocketMine-MP/releases/latest" : "https://api.github.com/repos/pmmp/PocketMine-MP/releases/tags/\(version)")!
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

private struct BedrockDownloadLinks: Decodable {
    struct Result: Decodable {
        struct DownloadLink: Decodable {
            let downloadType: String
            let downloadUrl: String
        }
        let links: [DownloadLink]
    }
    let result: Result
}
