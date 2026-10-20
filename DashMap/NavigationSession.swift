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
    /// Lane markings for the approach to the next maneuver, when known.
    @Published private(set) var lanes: LaneGuidance?
    /// Name, route number and speed limit of the road you're on, when known.
    @Published private(set) var roadInfo: RoadInfo?
    @Published private(set) var isSimulating = false
    /// Name of an added stop you haven't reached yet.
    @Published private(set) var stopName: String?
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

    private var laneFetchedStep = -1
    private var laneStep = -1
    private var laneTask: Task<Void, Never>?
    private var roadFetchedStep = -1
    private var roadTask: Task<Void, Never>?
    private var simulatedDistance = 0.0
    private let liveActivity = LiveActivityController()
    private var pendingStop: MKMapItem?
    private var stopOffset: Double?

    private var lastFix = Date()
    private var lastSpeed = 0.0
    private var isRerouting = false
    private var rerouteBackoff = 10.0
    private var lastRerouteAttempt = Date.distantPast
    private var lastFasterRouteCheck = Date()
    private var lastRouteSwitch = Date.distantPast

    static let fasterRouteCheckInterval = 90.0
    static let maxDeadReckoning = 120.0
    static let simulatedSpeed = 16.0   // m/s, about 36 mph

    init() {
        voice.enabled = voiceEnabled
        cancellable = location.$location.compactMap { $0 }.sink { [weak self] in self?.handle($0, simulated: false) }
        location.start()
    }

    /// Lanes to show now: only close to the turn, where they matter.
    var activeLanes: LaneGuidance? {
        guard let lanes, let state, state.distanceToManeuver < 800 else { return nil }
        return lanes
    }

    /// Over the posted limit by more than a small margin.
    var isSpeeding: Bool {
        guard let limit = roadInfo?.speedLimitKph else { return false }
        return speed * 3.6 > limit + 3
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

    func startNavigation(simulated: Bool = false) {
        guard let route else { return }
        isSimulating = simulated
        simulatedDistance = 0
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
        if isSimulating {
            advanceSimulation()
        } else if let here = location.location {
            handle(here, simulated: false)
        }
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
        resetLanes()
        clearStop()
        liveActivity.end()
        isSimulating = false
        phase = .idle
    }

    private func beginEngine(with route: Route) {
        self.route = route
        engine = NavigationEngine(route: route)
        announcer = Announcer()
        resetLanes()
    }

    private func resetLanes() {
        roadTask?.cancel()
        roadTask = nil
        roadInfo = nil
        roadFetchedStep = -1
        laneTask?.cancel()
        laneTask = nil
        lanes = nil
        laneStep = -1
        laneFetchedStep = -1
    }

    /// Looks up the road name, route number and speed limit once per step (a step stays on one road).
    private func updateRoad(_ s: NavigationState) {
        guard let route, roadFetchedStep != s.stepIndex else { return }
        roadFetchedStep = s.stepIndex
        roadTask?.cancel()
        roadInfo = nil

        let step = route.steps[s.stepIndex]
        let spot = route.position(atOffset: step.startOffset + min(60, (step.endOffset - step.startOffset) / 2))
        let index = s.stepIndex
        roadTask = Task {
            let result = await RoadService.fetch(near: spot.coordinate, bearing: spot.bearing)
            guard !Task.isCancelled, roadFetchedStep == index else { return }
            roadInfo = result
            roadTask = nil
        }
    }

    /// Feeds a fake GPS fix one second further along the route, for testing and demos.
    private func advanceSimulation() {
        guard let route else { return }
        simulatedDistance = min(route.distance, simulatedDistance + Self.simulatedSpeed)
        let p = route.position(atOffset: simulatedDistance)
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: p.bearing, speed: Self.simulatedSpeed, timestamp: Date()
        )
        handle(fix, simulated: true)
    }

    /// Looks up lanes once per step, when the turn is within ~1.2 km.
    private func updateLanes(_ s: NavigationState) {
        if s.stepIndex != laneStep {
            laneTask?.cancel()
            laneTask = nil
            lanes = nil
            laneStep = s.stepIndex
        }
        guard let route, laneFetchedStep != s.stepIndex, s.distanceToManeuver < 1200,
              s.status == .onRoute, s.nextManeuver != .arrive else { return }
        laneFetchedStep = s.stepIndex

        let step = s.stepIndex
        let maneuver = s.nextManeuver
        // A spot just before the turn identifies the road you're on and which way you travel along it.
        let spot = route.position(atOffset: route.steps[step].endOffset - 20)
        laneTask = Task {
            let result = await LaneService.fetch(near: spot.coordinate, bearing: spot.bearing, maneuver: maneuver)
            guard !Task.isCancelled, laneStep == step else { return }
            lanes = result
            laneTask = nil
        }
    }

    private func handle(_ loc: CLLocation, simulated: Bool) {
        guard simulated == isSimulating else { return }   // ignore real GPS during a simulated drive
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
        if isSimulating { advanceSimulation() }

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
        if let offset = stopOffset, s.progress >= offset - 20 { clearStop() }
        liveActivity.update(from: s, destination: destinationName, units: Units.current)
        updateRoad(s)
        updateLanes(s)
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

    // MARK: Stops

    func reportError(_ message: String) { errorMessage = message }

    /// Routes you → stop → destination so the added time can be shown before committing.
    func previewStop(_ item: MKMapItem) async -> StopPlan? {
        guard let here = carPosition ?? currentCoordinate, let destination, let state,
              let leg1 = try? await MapKitRouter.routes(from: here, to: item).first,
              let leg2 = try? await MapKitRouter.routes(from: Coordinate(item.placemark.coordinate), to: destination).first,
              let joined = Route.joined(leg1, leg2) else { return nil }
        return StopPlan(item: item, route: joined.route, joinOffset: joined.joinOffset, added: joined.route.duration - state.timeRemaining)
    }

    func commitStop(_ plan: StopPlan) {
        pendingStop = plan.item
        stopOffset = plan.joinOffset
        stopName = plan.item.name
        lastRouteSwitch = Date()
        beginEngine(with: plan.route)
    }

    private func clearStop() {
        pendingStop = nil
        stopOffset = nil
        stopName = nil
    }

    /// Fresh route from `origin` that still passes the added stop, if one is pending.
    private func routeKeepingStop(from origin: Coordinate) async throws -> (route: Route, joinOffset: Double?) {
        guard let destination else { throw MapKitRouter.RouterError.noRoute }
        if let stop = pendingStop,
           let leg1 = try await MapKitRouter.routes(from: origin, to: stop).first,
           let leg2 = try await MapKitRouter.routes(from: Coordinate(stop.placemark.coordinate), to: destination).first,
           let joined = Route.joined(leg1, leg2) {
            return (joined.route, joined.joinOffset)
        }
        guard let route = try await MapKitRouter.routes(from: origin, to: destination).first else { throw MapKitRouter.RouterError.noRoute }
        return (route, nil)
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
                let new = try await routeKeepingStop(from: loc.coordinate2D)
                guard phase == .navigating else { return }
                beginEngine(with: new.route)
                stopOffset = new.joinOffset
                rerouteBackoff = 10
            } catch {
                // Network or routing failure: keep the old route, retry with growing delay.
                rerouteBackoff = min(rerouteBackoff * 2, 60)
            }
        }
    }

    private func checkForFasterRoute(from loc: CLLocation, current: NavigationState) async {
        guard let destination, pendingStop == nil,
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
