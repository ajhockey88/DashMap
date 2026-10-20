import SwiftUI
import MapKit
import DashMapCore

/// A live driving map: the camera is pitched, rotated to the car's heading and glides with it every update,
/// like a navigation app. Used by the map screen and by the HUD's map mode.
struct DrivingMap: UIViewRepresentable {
    enum Style { case standard, hud }

    let style: Style
    let route: Route?
    let state: NavigationState?
    let car: Coordinate?
    let heading: Double
    let speed: Double
    /// Lanes painted on the road ahead of a turn (ribbon on the lane to use, arrows in every lane).
    var lanePaint: LanePaint?
    /// False once the user pans or zooms; the recenter button sets it back to true.
    @Binding var following: Bool

    func makeCoordinator() -> Coordinator { Coordinator(style: style, following: $following) }

    func makeUIView(context: Context) -> MKMapView {
        let c = context.coordinator
        let map = MKMapView()
        map.delegate = c
        map.showsUserLocation = false          // the car marker below replaces the blue dot
        map.showsCompass = false
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        switch style {
        case .standard:
            map.overrideUserInterfaceStyle = .dark
        case .hud:
            map.overrideUserInterfaceStyle = .dark
            map.mapType = .mutedStandard
            map.pointOfInterestFilter = .excludingAll
            map.isUserInteractionEnabled = false
        }
        for recognizer in [UIPanGestureRecognizer(), UIPinchGestureRecognizer(), UIRotationGestureRecognizer()] as [UIGestureRecognizer] {
            recognizer.addTarget(c, action: #selector(Coordinator.userGesture(_:)))
            recognizer.delegate = c
            map.addGestureRecognizer(recognizer)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.syncOverlays(map, route: route, state: state)
        c.syncLanes(map, paint: lanePaint)
        guard let car else { return }
        c.syncCar(map, at: car, heading: heading)
        if following {
            c.follow(map, car: car, heading: heading, speed: speed, distanceToManeuver: state?.distanceToManeuver)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private let style: Style
        private var following: Binding<Bool>
        private var overlayKey = ""
        private var routeOverlays: [MKOverlay] = []
        private var laneOverlays: [MKOverlay] = []
        private var laneKey = ""
        private var carAnnotation: CarAnnotation?
        private var distance = 650.0   // camera distance in meters, eased toward a speed-based target

        init(style: Style, following: Binding<Bool>) {
            self.style = style
            self.following = following
        }

        // MARK: Gestures

        @objc func userGesture(_ g: UIGestureRecognizer) {
            if g.state == .began, following.wrappedValue { following.wrappedValue = false }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // MARK: Camera

        func follow(_ map: MKMapView, car: Coordinate, heading: Double, speed: Double, distanceToManeuver: Double?) {
            guard map.bounds.width > 0 else { return }

            // Zoom out a little with speed, zoom in when a turn is close.
            var target = min(1_300, max(450, 450 + speed * 22))
            if let d = distanceToManeuver, d < 200 { target *= 0.65 }
            distance += (target - distance) * 0.15

            // Aim the camera ahead of the car so the car sits in the lower part of the screen.
            let center = Self.offset(car, bearing: heading, meters: distance * 0.28)
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                fromDistance: distance,
                pitch: style == .standard ? 55 : 45,
                heading: heading
            )
            UIView.animate(withDuration: 1.0, delay: 0, options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
                map.camera = camera
            }
        }

        private static func offset(_ c: Coordinate, bearing: Double, meters: Double) -> Coordinate {
            let r = bearing * .pi / 180
            let dLat = meters * cos(r) / 111_320
            let dLon = meters * sin(r) / (111_320 * max(0.1, cos(c.latitude * .pi / 180)))
            return Coordinate(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
        }

        // MARK: Car marker

        func syncCar(_ map: MKMapView, at car: Coordinate, heading: Double) {
            let coordinate = CLLocationCoordinate2D(latitude: car.latitude, longitude: car.longitude)
            let annotation: CarAnnotation
            if let existing = carAnnotation {
                annotation = existing
            } else {
                annotation = CarAnnotation(coordinate: coordinate)
                carAnnotation = annotation
                map.addAnnotation(annotation)
            }
            UIView.animate(withDuration: 1.0, delay: 0, options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
                annotation.coordinate = coordinate
                // The camera faces the car's heading while following, so the arrow points up; when the user
                // has rotated the map it keeps pointing the true way.
                let relative = (heading - map.camera.heading) * .pi / 180
                map.view(for: annotation)?.transform = CGAffineTransform(rotationAngle: relative)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is CarAnnotation else { return nil }
            let id = "car"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.image = Self.carImage(hud: style == .hud)
            view.displayPriority = .required
            view.zPriority = .max
            view.canShowCallout = false
            return view
        }

        private static func carImage(hud: Bool) -> UIImage {
            let size = CGSize(width: 44, height: 44)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let fill = hud ? UIColor(red: 0.29, green: 0.94, blue: 0.63, alpha: 1) : UIColor.systemBlue
                fill.withAlphaComponent(0.2).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
                let arrow = UIBezierPath()
                arrow.move(to: CGPoint(x: 22, y: 6))
                arrow.addLine(to: CGPoint(x: 34, y: 36))
                arrow.addLine(to: CGPoint(x: 22, y: 29))
                arrow.addLine(to: CGPoint(x: 10, y: 36))
                arrow.close()
                fill.setFill()
                UIColor.white.setStroke()
                arrow.lineWidth = 3
                arrow.lineJoinStyle = .round
                arrow.stroke()
                arrow.fill()
            }
        }

        // MARK: Route overlays

        /// The driven part of the route turns gray; only redrawn when the matched segment changes.
        func syncOverlays(_ map: MKMapView, route: Route?, state: NavigationState?) {
            guard let route else { return }
            let segment = state?.segment ?? 0
            let key = "\(route.polyline.count)-\(route.distance)-\(segment)"
            guard key != overlayKey else { return }
            overlayKey = key

            map.removeOverlays(routeOverlays)
            let all = route.mapCoordinates
            var done = Array(all[0...min(segment, all.count - 1)])
            var rest = Array(all[min(segment + 1, all.count - 1)...])
            if let snapped = state?.snapped {
                let p = CLLocationCoordinate2D(latitude: snapped.latitude, longitude: snapped.longitude)
                done.append(p)
                rest.insert(p, at: 0)
            }
            let traveled = MKPolyline(coordinates: done, count: done.count)
            traveled.title = "traveled"
            let remaining = MKPolyline(coordinates: rest, count: rest.count)
            remaining.title = "remaining"
            routeOverlays = [traveled, remaining]
            map.addOverlays(routeOverlays)
            // Keep the lane graphics above the route line.
            map.removeOverlays(laneOverlays)
            map.addOverlays(laneOverlays)
        }

        /// Lane ribbon and painted arrows, as real-world shapes so they get smaller with distance like road paint.
        func syncLanes(_ map: MKMapView, paint: LanePaint?) {
            let key: String
            if let paint, let first = paint.ribbons.first?.first {
                key = "\(paint.ribbons.count)-\(paint.arrows.count)-\(first.latitude)-\(first.longitude)"
            } else {
                key = ""
            }
            guard key != laneKey else { return }
            laneKey = key
            map.removeOverlays(laneOverlays)
            laneOverlays = []
            guard let paint else { return }

            func polygon(_ points: [Coordinate], _ title: String) -> MKPolygon {
                let coords = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let polygon = MKPolygon(coordinates: coords, count: coords.count)
                polygon.title = title
                return polygon
            }
            laneOverlays = paint.ribbons.map { polygon($0, "lane-ribbon") }
                + paint.arrows.filter { !$0.isActive }.map { polygon($0.points, "lane-arrow-off") }
                + paint.arrows.filter { $0.isActive }.map { polygon($0.points, "lane-arrow-on") }
            map.addOverlays(laneOverlays)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                switch polygon.title {
                case "lane-ribbon": renderer.fillColor = UIColor(red: 0.29, green: 0.94, blue: 0.63, alpha: 0.6)
                case "lane-arrow-on": renderer.fillColor = .white
                default: renderer.fillColor = UIColor(white: 0.55, alpha: 1)
                }
                renderer.strokeColor = nil
                return renderer
            }
            let renderer = MKPolylineRenderer(overlay: overlay)
            let traveled = overlay.title == "traveled"
            switch style {
            case .standard:
                renderer.strokeColor = traveled ? UIColor(white: 0.4, alpha: 1) : UIColor(red: 0.30, green: 0.60, blue: 1.0, alpha: 1)
                renderer.lineWidth = 9
            case .hud:
                renderer.strokeColor = traveled ? UIColor(white: 0.25, alpha: 1) : UIColor(red: 0.29, green: 0.94, blue: 0.63, alpha: 1)
                renderer.lineWidth = 11
            }
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}

final class CarAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}
