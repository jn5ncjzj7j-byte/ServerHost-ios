import Foundation
import Combine

@_silgen_name("server_runtime_start")
private func server_runtime_start(
    _ javaHome: UnsafePointer<CChar>,
    _ workingDirectory: UnsafePointer<CChar>,
    _ jarPath: UnsafePointer<CChar>,
    _ heapMB: Int32,
    _ callback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void,
    _ context: UnsafeMutableRawPointer?
) -> Int32

@_silgen_name("server_runtime_send_command")
private func server_runtime_send_command(_ command: UnsafePointer<CChar>) -> Int32

@MainActor
final class ServerRuntimeController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var output: [String] = []
    @Published var error: String?

    private let callback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { message, context in
        guard let context else { return }
        let controller = Unmanaged<ServerRuntimeController>.fromOpaque(context).takeUnretainedValue()
        let line = message.map { String(cString: $0) } ?? ""
        Task { @MainActor in
            controller.output.append(line)
            if controller.output.count > 500 {
                controller.output.removeFirst(controller.output.count - 500)
            }
            if line.contains("[ServerHost] EXIT:") {
                controller.isRunning = false
            }
        }
    }

    func start(profile: ServerProfile, heapMB: Double, onlineMode: Bool, maxPlayers: Int, port: String) {
        guard profile.edition == Edition.java.rawValue else {
            error = "The official Bedrock Linux server cannot execute on iPadOS. Bedrock downloads can be transferred to a Linux host."
            return
        }
        guard ["vanilla", "paper"].contains(profile.softwareID) else {
            error = "This Java server type does not have an installer/runtime setup yet."
            return
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let serverDirectory = documents.appendingPathComponent("Servers", isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: profile.installedFile).deletingLastPathComponent().lastPathComponent, isDirectory: true)
        let jarURL = documents.appendingPathComponent("Servers", isDirectory: true)
            .appendingPathComponent(profile.installedFile)
        guard FileManager.default.fileExists(atPath: jarURL.path) else {
            error = "The installed server JAR could not be found."
            return
        }

        let eulaURL = serverDirectory.appendingPathComponent("eula.txt")
        if !FileManager.default.fileExists(atPath: eulaURL.path) {
            try? "eula=false\n".write(to: eulaURL, atomically: true, encoding: .utf8)
        }
        let eula = (try? String(contentsOf: eulaURL, encoding: .utf8)) ?? ""
        guard eula.range(of: #"(?m)^eula\s*=\s*true\s*$"#, options: .regularExpression) != nil else {
            error = "Minecraft requires eula=true before the server can start. Ask a parent or guardian to review the Minecraft EULA, then edit eula.txt in Files."
            return
        }

        let propertiesURL = serverDirectory.appendingPathComponent("server.properties")
        var properties = (try? String(contentsOf: propertiesURL, encoding: .utf8)) ?? ""
        var values = [String: String]()
        for line in properties.components(separatedBy: .newlines) where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        values["online-mode"] = onlineMode ? "true" : "false"
        values["max-players"] = String(max(1, min(1_000_000, maxPlayers)))
        values["server-port"] = Int(port).map { String(max(1, min(65535, $0))) } ?? "25565"
        for key in ["online-mode", "max-players", "server-port"] {
            properties = properties.replacingOccurrences(of: #"(?m)^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=.*$"#, with: "", options: .regularExpression)
        }
        let updated = properties.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + values.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n") + "\n"
        do {
            try updated.write(to: propertiesURL, atomically: true, encoding: .utf8)
        } catch {
            self.error = "Could not write server.properties: \(error.localizedDescription)"
            return
        }

        let javaVersion = profile.javaVersion ?? JavaCompatibility.required(for: profile.version)
        guard let resources = Bundle.main.resourceURL else {
            error = "The app bundle resource directory is missing."
            return
        }
        let javaHome = resources.appendingPathComponent("JavaRuntimes/java-\(javaVersion)-openjdk", isDirectory: true)
        let java8JLI = javaHome.appendingPathComponent("lib/jli/libjli.dylib")
        let newerJLI = javaHome.appendingPathComponent("lib/libjli.dylib")
        guard FileManager.default.fileExists(atPath: java8JLI.path) || FileManager.default.fileExists(atPath: newerJLI.path) else {
            error = "Java \(javaVersion) runtime is not bundled in this build. Rebuild the IPA after the runtime download step succeeds."
            return
        }

        output.removeAll()
        output.append("Starting \(profile.name) with Java \(javaVersion)...")
        isRunning = true
        let result = javaHome.path.withCString { javaPath in
            serverDirectory.path.withCString { directoryPath in
                jarURL.path.withCString { serverPath in
                    server_runtime_start(javaPath, directoryPath, serverPath, Int32(DeviceMemoryPolicy.clampedAllocation(heapMB)), callback, Unmanaged.passUnretained(self).toOpaque())
                }
            }
        }
        if result != 0 {
            isRunning = false
            error = "Could not start the Java runtime (code \(result))."
        }
    }

    func sendCommand(_ command: String) {
        guard isRunning else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        trimmed.withCString { _ = server_runtime_send_command($0) }
    }
}
