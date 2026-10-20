# DashMap

A HUDWAY-style heads-up display for iPhone, driven by Apple Maps (MapKit).
Lay the phone on the dashboard; the mirrored display reflects off the windshield.

## Features (MVP)
- Destination search (MapKit local search)
- Driving route (MKDirections), preview on an Apple map
- HUD: big maneuver arrow, distance to turn, instruction, speed, ETA, distance left
- Mirror / normal toggle, km/mi toggle, max brightness and screen kept awake
- Voice prompts, off-route detection and automatic reroute, background location

## Setup
No API keys or accounts needed; routing and search use Apple Maps (MapKit).
1. `brew install xcodegen && xcodegen && open DashMap.xcodeproj`
2. Set your signing team and run on a real device (the simulator can fake a drive via Debug > Location).

Core logic (`Packages/DashMapCore`) has no dependencies: `swift test` runs on macOS.

## Not yet built
Speed limits, lane guidance, traffic/camera alerts, saved places, CarPlay, Apple Watch, landscape layout tuning.

## Notes
MapKit routes carry no maneuver type, so turn direction is inferred from the heading change between
steps (`MapKitRouter`), with keyword overrides for roundabouts, merges and U-turns. Instruction text
is localized by Apple; the keyword overrides only match English.
