import Combine
import CoreLocation
import DashMapCore
import Foundation
import MapKit
import UIKit

@MainActor
final class NavigationSession: ObservableObject {
    enum Phase { case idle, loading, preview, navigating }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var routes: [Route] = []
    @Published var selectedRouteIndex = 0
    @Published private(set) var route: Route?
    @Published private(set) var state: NavigationState?
    @Published private(set) var speed: Double = 0
    @Published private(set) var gpsLost = false
    /// Where to draw the car and which way it faces (degrees clockwise from north); smoothed for the map camera.
    @Published private(set) var carPosition: Coordinate?
    @Published private(set) var carHeading: Double = 0
    @Published var errorMessage: String?
    @Published private(set) var destinationName = ""
    @Published var voiceEnabled = UserDefaults.standard.object(forKey: "voice.enabled") as? Bool ?? true {
        didSet {
            voice.enabled = voiceEnabled
            UserDefaults.standard.set(voiceEnabled, forKey: "voice.enabled")
        }
    }

    let location = LocationService()
    private let voice = Voice()
    private var engine: NavigationEngine?
    private var announcer = Announcer()
    private var destination: MKMapItem?
    private var cancellable: AnyCancellable?
    private var ticker: Task<Void, Never>?

    private var lastFix = Date()
    private var lastSpeed = 0.0
    private var isRerouting = false
    private var rerouteBackoff = 10.0
    private var lastRerouteAttempt = Date.distantPast
    private var lastFasterRouteCheck = Date()
    private var lastRouteSwitch = Date.distantPast

    static let fasterRouteCheckInterval = 90.0
    static let maxDeadReckoning = 120.0

    init() {
        voice.enabled = voiceEnabled
        cancellable = location.$location.compactMap { $0 }.sink { [weak self] in self?.handle($0) }
        location.start()
    }

    var currentCoordinate: Coordinate? { location.location?.coordinate2D }

    // MARK: Planning

    func plan(to destination: MKMapItem) async {
        guard let here = location.location else {
            errorMessage = "Waiting for your location…"
            return
        }
        phase = .loading
        self.destination = destination
        destinationName = destination.name ?? "Destination"
        do {
            routes = try await MapKitRouter.routes(from: here.coordinate2D, to: destination)
            selectedRouteIndex = 0
            route = routes[0]
            phase = .preview
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    func selectRoute(_ index: Int) {
        guard routes.indices.contains(index) else { return }
        selectedRouteIndex = index
        route = routes[index]
    }

    // MARK: Navigating

    func startNavigation() {
        guard let route else { return }
        beginEngine(with: route)
        state = nil
        carPosition = nil
        phase = .navigating
        lastFix = Date()
        lastFasterRouteCheck = Date()
        location.setBackground(true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.tick()
            }
        }
        if let here = location.location { handle(here) }
    }

    func stopNavigation() {
        ticker?.cancel()
        ticker = nil
        location.setBackground(false)
        engine = nil
        state = nil
        route = nil
        routes = []
        destination = nil
        gpsLost = false
        carPosition = nil
        phase = .idle
    }

    private func beginEngine(with route: Route) {
        self.route = route
        engine = NavigationEngine(route: route)
        announcer = Announcer()
    }

    private func handle(_ loc: CLLocation) {
        lastFix = Date()
        gpsLost = false
        speed = max(0, loc.speed)
        lastSpeed = speed
        guard phase == .navigating, let engine else { return }

        let s = engine.update(
            location: loc.coordinate2D,
            accuracy: loc.horizontalAccuracy,
            course: loc.course >= 0 ? loc.course : nil,
            speed: speed
        )
        apply(s, from: loc)
    }

    /// Runs once a second: dead-reckons through GPS gaps and periodically looks for a faster route.
    private func tick() {
        guard phase == .navigating, let engine else { return }

        let gap = Date().timeIntervalSince(lastFix)
        if gap > 2 {
            gpsLost = true
            if lastSpeed > 1, gap <= Self.maxDeadReckoning {
                apply(engine.extrapolate(speed: lastSpeed, since: gap), from: nil)
            }
        }

        if let state, state.status == .onRoute, !isRerouting, !gpsLost,
           Date().timeIntervalSince(lastFasterRouteCheck) > Self.fasterRouteCheckInterval,
           Date().timeIntervalSince(lastRouteSwitch) > 300,
           let here = location.location {
            lastFasterRouteCheck = Date()
            Task { await checkForFasterRoute(from: here, current: state) }
        }
    }

    private func updateCar(_ s: NavigationState, from loc: CLLocation?) {
        // Sit on the road while we agree with the route; fall back to the raw fix when clearly elsewhere.
        carPosition = s.offRouteDistance < 30 ? s.snapped : (loc?.coordinate2D ?? s.snapped)

        var target: Double?
        if let loc, loc.course >= 0, loc.speed > 1.5 {
            target = loc.course
        } else if let route, route.segmentBearings.indices.contains(s.segment) {
            target = route.segmentBearings[s.segment]
        }
        guard let target else { return }
        if state == nil {   // first fix of this trip: snap to it instead of easing from 0°
            carHeading = target
        } else {
            carHeading += 0.4 * Geo.turnAngle(before: carHeading, after: target)
        }
        carHeading = (carHeading + 360).truncatingRemainder(dividingBy: 360)
    }

    private func apply(_ s: NavigationState, from loc: CLLocation?) {
        updateCar(s, from: loc)
        state = s
        if let a = announcer.next(for: s, speed: speed) {
            voice.speak(a, units: Units.current)
        }
        switch s.status {
        case .arrived:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ticker?.cancel()
            Task { try? await Task.sleep(nanoseconds: 4_000_000_000); self.stopNavigation() }
        case .offRoute:
            if let loc { reroute(from: loc) }
        case .onRoute:
            break
        }
    }

    // MARK: Rerouting

    private func reroute(from loc: CLLocation) {
        guard !isRerouting, let destination,
              Date().timeIntervalSince(lastRerouteAttempt) > rerouteBackoff else { return }
        isRerouting = true
        lastRerouteAttempt = Date()
        voice.speak("Rerouting")
        Task {
            defer { isRerouting = false }
            do {
                let new = try await MapKitRouter.routes(from: loc.coordinate2D, to: destination)
                guard phase == .navigating else { return }
                beginEngine(with: new[0])
                rerouteBackoff = 10
            } catch {
                // Network or routing failure: keep the old route, retry with growing delay.
                rerouteBackoff = min(rerouteBackoff * 2, 60)
            }
        }
    }

    private func checkForFasterRoute(from loc: CLLocation, current: NavigationState) async {
        guard let destination,
              let candidates = try? await MapKitRouter.routes(from: loc.coordinate2D, to: destination),
              let best = candidates.min(by: { $0.duration < $1.duration }),
              phase == .navigating, state?.status == .onRoute else { return }

        let saving = current.timeRemaining - best.duration
        guard saving > max(120, current.timeRemaining * 0.1) else { return }
        beginEngine(with: best)
        lastRouteSwitch = Date()
        voice.speak("Switching to a faster route. It saves \(formatDuration(saving)).")
    }
}
