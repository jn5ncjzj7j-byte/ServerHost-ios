import SwiftUI

@main
struct ServerHostApp: App {
    @StateObject private var serverStore = ServerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverStore)
                .preferredColorScheme(.dark)
        }
    }
}
