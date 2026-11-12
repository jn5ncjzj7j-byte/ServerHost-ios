import Foundation
import Combine
import Darwin

@_silgen_name("server_runtime_start")
private func server_runtime_start(_ javaHome: UnsafePointer<CChar>, _ workingDirectory: UnsafePointer<CChar>, _ jarPath: UnsafePointer<CChar>, _ heapMB: Int32, _ callback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void, _ context: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("server_runtime_send_command")
private func server_runtime_send_command(_ command: UnsafePointer<CChar>) -> Int32

@MainActor
final class ServerRuntimeController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var output: [String] = []
    @Published private(set) var onlinePlayers = 0
    @Published private(set) var maximumPlayers = 20
    @Published private(set) var memoryUsageMB = 0
    @Published private(set) var localIPAddress = "Not connected"
    @Published var error: String?

    private let callback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { message, context in
        guard let context else { return }
        let controller = Unmanaged<ServerRuntimeController>.fromOpaque(context).takeUnretainedValue()
        let line = message.map { String(cString: $0) } ?? ""
        Task { @MainActor in controller.consume(line) }
    }

    func refreshStats() {
        localIPAddress = Self.findLocalIPv4()
        var information = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        if result == KERN_SUCCESS {
            memoryUsageMB = Int(information.resident_size / 1_048_576)
        }
    }

    func needsEULAAcceptance(for profile: ServerProfile) -> Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let installedURL = documents.appendingPathComponent("Servers").appendingPathComponent(profile.installedFile)
        let eulaURL = installedURL.deletingLastPathComponent().appendingPathComponent("eula.txt")
        if !FileManager.default.fileExists(atPath: eulaURL.path) {
            do {
                try "eula=false\n".write(to: eulaURL, atomically: true, encoding: .utf8)
            } catch {
                self.error = "Could not create eula.txt: \(error.localizedDescription)"
            }
            return true
        }
        let contents = (try? String(contentsOf: eulaURL, encoding: .utf8)) ?? ""
        return contents.range(of: #"(?mi)^\\s*eula\\s*=\\s*true\\s*$"#, options: .regularExpression) == nil
    }

    func acceptEULA(for profile: ServerProfile) -> Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let installedURL = documents.appendingPathComponent("Servers").appendingPathComponent(profile.installedFile)
        let eulaURL = installedURL.deletingLastPathComponent().appendingPathComponent("eula.txt")
        do {
            try "eula=true\\n".write(to: eulaURL, atomically: true, encoding: .utf8)
            error = nil
            return true
        } catch {
            self.error = "Could not save EULA acceptance: \\(error.localizedDescription)"
            return false
        }
    }

    func configureBedrock(profile: ServerProfile, port: String, maxPlayers: Int) {
        guard profile.edition == Edition.bedrock.rawValue else {
            error = "Select a Bedrock server profile first."
            return
        }
        let numericPort = Int(port).map { min(65535, max(1, $0)) } ?? 19132
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Servers", isDirectory: true)
        let directory = root.appendingPathComponent(profile.installedFile).deletingLastPathComponent()
        let propertiesURL = directory.appendingPathComponent("server.properties")
        var properties = (try? String(contentsOf: propertiesURL, encoding: .utf8)) ?? ""
        let values = [
            "server-port": String(numericPort),
            "server-portv6": String(numericPort),
            "max-players": String(min(1_000_000, max(1, maxPlayers)))
        ]
        for (key, value) in values {
            let pattern = #"(?m)^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=.*$"#
            properties = properties.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            properties += "\(key)=\(value)\n"
        }
        do {
            try properties.trimmingCharacters(in: .whitespacesAndNewlines).appending("\n").write(to: propertiesURL, atomically: true, encoding: .utf8)
            maximumPlayers = Int(values["max-players"] ?? "20") ?? 20
            error = "Bedrock settings saved: UDP port \(numericPort), maximum \(maximumPlayers) players. The official Bedrock binary is Linux-only and cannot start on iPadOS."
        } catch {
            self.error = "Could not save Bedrock server.properties: \(error.localizedDescription)"
        }
    }

    func start(profile: ServerProfile, heapMB: Double, onlineMode: Bool, maxPlayers: Int, port: String) {
        guard profile.edition == Edition.java.rawValue else {
            error = "Use Prepare Bedrock Settings for Bedrock. The official Bedrock Linux binary cannot execute on iPadOS."
            return
        }
        guard ["vanilla", "paper"].contains(profile.softwareID) else {
            error = "This Java server type does not have an installer/runtime setup yet."
            return
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("Servers", isDirectory: true)
        let installedURL = root.appendingPathComponent(profile.installedFile)
        let serverDirectory = installedURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: installedURL.path) else {
            error = "The installed server JAR could not be found."
            return
        }

        let eulaURL = serverDirectory.appendingPathComponent("eula.txt")
        if !FileManager.default.fileExists(atPath: eulaURL.path) {
            try? "eula=false\n".write(to: eulaURL, atomically: true, encoding: .utf8)
        }
        let eula = (try? String(contentsOf: eulaURL, encoding: .utf8)) ?? ""
        guard eula.range(of: #"(?m)^eula\s*=\s*true\s*$"#, options: .regularExpression) != nil else {
            error = "Minecraft requires eula=true before the server can start. Review the Minecraft EULA with a parent or guardian, then update eula.txt in Files."
            return
        }

        let propertiesURL = serverDirectory.appendingPathComponent("server.properties")
        var properties = (try? String(contentsOf: propertiesURL, encoding: .utf8)) ?? ""
        let numericPort = Int(port).map { min(65535, max(1, $0)) } ?? 25565
        let values = [
            "online-mode": onlineMode ? "true" : "false",
            "max-players": String(min(1_000_000, max(1, maxPlayers))),
            "server-port": String(numericPort)
        ]
        for (key, value) in values {
            let pattern = #"(?m)^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=.*$"#
            properties = properties.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            properties += "\(key)=\(value)\n"
        }
        do {
            try properties.trimmingCharacters(in: .whitespacesAndNewlines).appending("\n").write(to: propertiesURL, atomically: true, encoding: .utf8)
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
            error = "Java \(javaVersion) runtime is missing from this build."
            return
        }

        output.removeAll()
        onlinePlayers = 0
        maximumPlayers = values["max-players"].flatMap(Int.init) ?? 20
        error = nil
        refreshStats()
        output.append("Starting \(profile.name) with Java \(javaVersion)...")
        isRunning = true
        let result = javaHome.path.withCString { javaPath in
            serverDirectory.path.withCString { directoryPath in
                installedURL.path.withCString { serverPath in
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

    private func consume(_ line: String) {
        output.append(line)
        if output.count > 500 { output.removeFirst(output.count - 500) }
        let patterns = [
            #"There are\s+(\d+)\s+of a max of\s+(\d+)\s+players online"#,
            #"There are\s+(\d+)\s*/\s*(\d+)\s+players online"#,
            #"Players:\s*(\d+)\s*/\s*(\d+)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let onlineRange = Range(match.range(at: 1), in: line),
                  let maxRange = Range(match.range(at: 2), in: line),
                  let online = Int(line[onlineRange]),
                  let maximum = Int(line[maxRange]) else { continue }
            onlinePlayers = online
            maximumPlayers = maximum
            break
        }
        if line.contains("[ServerHost] EXIT:") {
            isRunning = false
            onlinePlayers = 0
        }
        refreshStats()
    }

    private static func findLocalIPv4() -> String {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return "Not connected" }
        defer { freeifaddrs(interfaces) }
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: item.pointee.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            let socketAddress = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var ipAddress = socketAddress.sin_addr
            guard inet_ntop(AF_INET, &ipAddress, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            return String(cString: buffer)
        }
        return "Not connected"
    }
}
