import Foundation

enum Config {
    /// Injected from Config/Secrets.xcconfig via Info.plist.
    static var googleAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GOOGLE_API_KEY") as? String ?? ""
    }
}
