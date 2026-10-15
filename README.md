# Pubtram

A native SwiftUI iPhone/iPad client for the Czech public-transport timetables behind
[seznam.cz/jizdnirady](https://www.seznam.cz/jizdnirady/). It needs iOS 26+ and Xcode 27.

Open `Pubtram.xcodeproj` and run the `Pubtram` scheme. There are no dependencies.

## Features

- **Search on its own page.** The home page holds only the search card and your favorites
  (each favorite shows a live preview of its next connection). Results and connection detail are
  pushed pages on iPhone; on iPad they sit in a sidebar stack next to the detail.
- **Multi-place search.** "Odkud" and "Kam" each accept up to 4 alternatives (⊕ button), e.g.
  "Anděl or Na Knížecí → Letňany". All combinations are searched in parallel and merged.
- **Departure boards** that combine several stops and can be limited to chosen lines
  (e.g. trams 9 and 12 from either stop).
- **Results:**
  - a proportional journey bar that also reads well on 10-hour, 5-transfer trips
  - day sections, sorting, line filter and a "fastest" tag
  - transfers flagged as tight or missed based on live delays
- **Detail:**
  - a timeline with platforms/tracks, live and predicted delays, disruption notices and explicit waits
  - per-carrier ticket links
  - a map with real route shapes and live vehicle positions
- **System integration:**
  - widgets: departures (Home and Lock Screen) and favorite route
  - a trip Live Activity with Dynamic Island
  - Siri/Shortcuts actions ("Kdy mi to jede v Pubtram"), home-screen quick actions, Spotlight
    for favorites, and `pubtram://` deep links

## Project layout

| Folder | Contents |
|---|---|
| `Shared/` | API client, models, persistence (app group), shared views and intents. Compiled into the app *and* the widget extension |
| `Pubtram/` | App: navigation, view models, screens, Shortcuts |
| `PubtramWidgets/` | Widget extension: widgets and Live Activity |
| `Config/` | Info.plists and entitlements (app group `group.dev.frnoch.pubtram`) |

To run on a device, set your team and change the bundle IDs and the app group to your own.

## Backend API (unofficial, reverse-engineered)

Base URL: `https://jizdnirady.seznam.cz`. The web app sends binary FastRPC, but the server also
speaks plain **XML-RPC**, which is what `Shared/API/RPCValue.swift` implements.

| Call | Purpose |
|---|---|
| `GET /suggest?phrase=…&type=municipality\|address\|poi\|area\|firm\|pubt` | Place autocomplete (JSON) |
| `POST /routept/` `getRoutesOpt(date, isDeparture, {start,end,mid,index,count}, options)` | Connections. A negative `index` returns earlier ones |
| `getTripInfo([{tripId: partDescription, time}])` | Live info: delay (s), platforms (code 400), predictions (500), notices |
| `getTripDetail(partDescription, {startindex,endindex,time})` | Trip stops and geometry (`geom` = the ridden part) |
| `getWalkGeom({start:{x,y}, end:{x,y}})` | Walking geometry |
| `getStopDepartures(date, {start,end,mid,index,count}, {version:3})` | Departure board (not used by the website) |

Geometry strings use Mapy.cz's compact polyline encoding (see `Shared/API/GeometryDecoder.swift`).
Because this API is undocumented, it may change without notice.
