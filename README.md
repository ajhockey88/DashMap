# DashMap

A turn-by-turn navigation app for iPhone with a **windshield HUD**. Lay the phone flat on the dashboard and the
mirrored display reflects off the windshield. Routing and search use Apple Maps (MapKit), so no API keys or
accounts are needed.

> **Status:** the app and its unit tests build in CI. It has not yet been tested on a real drive. Do not rely on
> it as your only navigation, and do not operate it while driving.

## Features

**Navigation**
- Destination search, recent places, Home and Work shortcuts
- Route preview with alternatives, arrival times and a "Fastest" tag
- Voice prompts that chain close turns ("turn right, then turn left")
- Off-route detection and automatic reroute; periodic check for a faster route
- Dead reckoning through GPS dropouts (tunnels, garages), flagged on screen
- Search along the route (gas, food, coffee, EV charging, parking) and add a stop with the exact added time shown
- Lock screen and Dynamic Island turn display (Live Activity)

**Two driving displays**
- **Map:** a tilted driving camera that follows the car's heading, with the driven part of the route grayed out
- **HUD:** black, high-contrast, optionally mirrored for the windshield, in two styles: big arrows and text, or a dark moving map

**Road information** (from OpenStreetMap, where mapped)
- Lane guidance: which lanes turn and which go straight
- Current street name, highway or route number, and speed limit (the speed turns red when you're over it)

**Other**
- Dark interface throughout; settings for units, voice, start display, HUD style and mirroring
- **Simulate drive** on the route preview replays a route as fake GPS, to test indoors

## Install

You need an iPhone on iOS 17 or later. There is no Mac requirement: GitHub builds the app.

1. On GitHub, open **Actions**, pick the latest successful **Build** run, and download an artifact:
   - `DashMap-ipa-no-widget`: use this with a free Apple ID (one App ID, fewer sideloading problems)
   - `DashMap-ipa-with-widget`: includes the Dynamic Island widget; needs a paid developer account
2. The `.ipa` is **unsigned**. Sign and install it with a tool such as [Sideloadly](https://sideloadly.io) using your Apple ID.
   Free Apple IDs allow 3 sideloaded apps at once and expire after 7 days. A paid Apple Developer account removes
   those limits and allows TestFlight.

## Build from source

On a Mac with Xcode 16 or later:

```
brew install xcodegen
xcodegen
open DashMap.xcodeproj
```

Set your signing team on both the `DashMap` and `DashMapWidgets` targets and run on a device. Without a Mac, push to
GitHub: `.github/workflows/build.yml` runs the unit tests, compiles the app and widget, and packages the unsigned `.ipa` files.

The core logic needs no Apple frameworks: `swift test --package-path Packages/DashMapCore`.

## How it works

| Part | What it does |
| --- | --- |
| `Packages/DashMapCore` | Dependency-free Swift package: geometry, route model, route matching, off-route detection, dead reckoning, announcements, lane and road parsing. Unit tested. |
| `DashMap/` | The SwiftUI app: location, MapKit routing and search, voice, the map and HUD screens, settings. |
| `DashMapWidgets/` | Live Activity widget for the lock screen and Dynamic Island. |
| `Shared/` | Activity attributes shared by the app and widget. |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec; the `.xcodeproj` is generated, not committed. |

MapKit route steps carry no turn type, so left, right and U-turn are inferred from the change in heading between
steps, with keyword overrides for roundabouts and merges (English instruction text only).

## Data sources and limits

- **Apple Maps (MapKit):** routes (travel times account for current traffic), search and the map. No traffic colors are drawn: MapKit provides none for a route. Apple rate-limits route requests per app.
- **OpenStreetMap via the public Overpass API:** lanes, road names, route numbers and speed limits. One small
  query per route step. Coverage depends on local mapping, so some roads show nothing and some data may be out of
  date. The public server is for light use; a public release should use a provider or its own server.
  Data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), available under the ODbL.
- **Not available:** MapKit offers no speed-limit, lane or camera data of its own, no offline maps and no CarPlay
  navigation without Apple's approval.

## Privacy

Location is used on the device to guide you. The app sends route start and end points to Apple Maps and
small location queries to the Overpass server. There is no account, analytics or advertising.

## License

[MIT](LICENSE) © 2026 ajhockey88. OpenStreetMap data is separately licensed under the ODbL.
