# DashMap

A HUDWAY-style heads-up display for iPhone, driven by Google Maps Platform.
Lay the phone on the dashboard; the mirrored display reflects off the windshield.

## Features (MVP)
- Destination search (Places API New autocomplete)
- Traffic-aware driving route (Routes API), preview on a Google Map
- HUD: big maneuver arrow, distance to turn, instruction, speed, ETA, distance left
- Mirror / normal toggle, km/mi toggle, max brightness and screen kept awake
- Voice prompts, off-route detection and automatic reroute, background location

## Setup
1. In Google Cloud enable **Maps SDK for iOS**, **Routes API**, **Places API (New)**; create an API key
   restricted to your bundle ID.
2. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and paste the key.
3. `brew install xcodegen && xcodegen && open DashMap.xcodeproj`
4. Run on a real device (simulator can simulate drives via Debug > Location).

Core logic (`Packages/DashMapCore`) has no dependencies: `swift test` runs on macOS.

## Not yet built
Speed limits, lane guidance, traffic/camera alerts, saved places, CarPlay, Apple Watch, landscape layout tuning.

## Google terms caveat
This app computes guidance itself from Routes API results and the device's GPS. Google Maps Platform
terms have restricted real-time, turn-by-turn navigation built on the Routes/Directions APIs, and
Google's licensed route is the **Navigation SDK for iOS**. Confirm current terms before shipping to
the App Store. If you adopt the Navigation SDK, replace `NavigationEngine` with its turn/step
callbacks and keep `HUDView` as is.
