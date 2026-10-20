import Combine
import CoreLocation
import DashMapCore
import Foundation

@MainActor
final class NavigationSession: ObservableObject {
    enum Phase { case idle, loading, preview, navigating }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var route: Route?
    @Published private(set) var state: NavigationState?
    @Published private(set) var speed: Double = 0
    @Published var errorMessage: String?
    @Published var voiceEnabled = true { didSet { voice.enabled = voiceEnabled } }

    let location = LocationService()
    private let voice = Voice()
    private var engine: NavigationEngine?
    private var announcer = Announcer()
    private var destination: RoutesAPI.Destination?
    private var lastReroute = Date.distantPast
    private var cancellable: AnyCancellable?

    init() {
        cancellable = location.$location.compactMap { $0 }.sink { [weak self] in self?.handle($0) }
        location.start()
    }

    var currentCoordinate: Coordinate? { location.location?.coordinate2D }

    func plan(to destination: RoutesAPI.Destination) async {
        guard let here = location.location else {
            errorMessage = "Waiting for your location…"
            return
        }
        phase = .loading
        self.destination = destination
        do {
            route = try await fetchRoute(from: here, to: destination)
            phase = .preview
        } catch {
            errorMessage = Self.describe(error)
            phase = .idle
        }
    }

    func startNavigation() {
        guard let route else { return }
        engine = NavigationEngine(route: route)
        announcer = Announcer()
        state = nil
        phase = .navigating
        location.setBackground(true)
        if let here = location.location { handle(here) }
    }

    func stopNavigation() {
        location.setBackground(false)
        engine = nil
        state = nil
        route = nil
        destination = nil
        phase = .idle
    }

    private func fetchRoute(from here: CLLocation, to destination: RoutesAPI.Destination) async throws -> Route {
        let request = try RoutesAPI.makeRequest(
            apiKey: Config.googleAPIKey,
            origin: here.coordinate2D,
            heading: here.course >= 0 && here.speed > 1 ? here.course : nil,
            destination: destination,
            languageCode: Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        )
        let (data, _) = try await URLSession.shared.data(for: request)
        return try RoutesAPI.parse(data)
    }

    private func handle(_ loc: CLLocation) {
        speed = max(0, loc.speed)
        guard phase == .navigating, let engine else { return }

        let s = engine.update(location: loc.coordinate2D, accuracy: loc.horizontalAccuracy)
        state = s

        if let a = announcer.next(for: s, speed: speed) {
            voice.speak(a, units: Units.localeDefault)
        }
        if s.status == .arrived {
            Task { try? await Task.sleep(nanoseconds: 4_000_000_000); self.stopNavigation() }
        } else if s.status == .offRoute, Date().timeIntervalSince(lastReroute) > 10, let destination {
            lastReroute = Date()
            voice.speak("Rerouting")
            Task {
                guard let new = try? await fetchRoute(from: loc, to: destination), phase == .navigating else { return }
                route = new
                self.engine = NavigationEngine(route: new)
                announcer = Announcer()
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case RoutesAPI.Failure.noRoute: return "No driving route found."
        case RoutesAPI.Failure.server(let message): return message
        default: return error.localizedDescription
        }
    }
}
