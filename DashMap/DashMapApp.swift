import SwiftUI

@main
struct DashMapApp: App {
    @StateObject private var session = NavigationSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
