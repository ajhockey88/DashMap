import SwiftUI
import GoogleMaps

@main
struct DashMapApp: App {
    @StateObject private var session = NavigationSession()

    init() {
        GMSServices.provideAPIKey(Config.googleAPIKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(session)
        }
    }
}
