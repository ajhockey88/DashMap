# DashMap

A HUDWAY-style heads-up display for iPhone, driven by Apple Maps (MapKit).
Lay the phone on the dashboard; the mirrored display reflects off the windshield.

## Features (MVP)
- Destination search (MapKit local search)
- Driving route (MKDirections), preview on an Apple map
- HUD: big maneuver arrow, distance to turn, instruction, speed, ETA, distance left
- Mirror / normal toggle, km/mi toggle, max brightness and screen kept awake
- Voice prompts, off-route detection and automatic reroute, background location

## Interface
- Dark theme throughout (dark map too), one mint accent shared with the HUD and icon
- Home screen with search, recent places and Home/Work shortcuts (touch and hold a recent to set them)
- Route cards with time, distance, arrival and a "Fastest" tag; choose Map or HUD before pressing Start
- Settings: units (auto/mi/km), voice, start display, HUD style, windshield mirroring
- Location-off banner with a shortcut to Settings; confirm before ending navigation; haptics on start/arrival

## Lane guidance
Lane arrows (which lanes turn, which go straight, which to use) near each turn, on the map screen and both HUD styles.
Data comes from OpenStreetMap `turn:lanes` tags via the public Overpass API (one query per turn, no key). It only
appears where the road has been mapped with lanes; elsewhere nothing is shown. Data © OpenStreetMap contributors.
MapKit itself exposes no lane data; Mapbox's Navigation SDK would be the more complete (paid) source.

## Robustness
- Heading-aware road matching (picks the leg you're travelling along on out-and-back roads)
- Dead reckoning through GPS dropouts (tunnels, garages), flagged in the UI
- Reroute only on sustained deviation; retries with backoff if the network fails
- Checks for a faster route every 90 s and switches when it saves 2+ min (or 10%)
- Alternative routes in preview, "then…" chained prompts for close turns
- Live map view: pitched camera that rotates with the car's heading and glides with it (zoom eases out with
  speed and in before turns), live traffic, traveled part grayed; pan to explore, tap locate to re-follow
- HUD has two styles, "Arrows" (big arrow + text) and "Map" (dark moving map + compact banner); both can be mirrored

## Setup
No API keys or accounts needed; routing and search use Apple Maps (MapKit).
1. `brew install xcodegen && xcodegen && open DashMap.xcodeproj`
2. Set your signing team and run on a real device (the simulator can fake a drive via Debug > Location).

Core logic (`Packages/DashMapCore`) has no dependencies: `swift test` runs on macOS.

## Not yet built
Speed limits (MapKit exposes none), camera alerts, saved places, CarPlay, Apple Watch, landscape layout tuning.

## Notes
MapKit routes carry no maneuver type, so turn direction is inferred from the heading change between
steps (`MapKitRouter`), with keyword overrides for roundabouts, merges and U-turns. Instruction text
is localized by Apple; the keyword overrides only match English.
