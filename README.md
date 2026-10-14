# Pubtram

A native SwiftUI iPhone/iPad client for the Czech public-transport timetables behind
[seznam.cz/jizdnirady](https://www.seznam.cz/jizdnirady/). It needs iOS 26+ and Xcode 27.

Open `Pubtram.xcodeproj` and run the `Pubtram` scheme. There are no dependencies.

## Features

- Connection search with autocomplete (stops, addresses, POIs), current location, optional "via"
  stop, departure/arrival time, transport-mode filters, max transfers and accessibility options
- Earlier/later connections, with live delays, platforms/tracks, disruption notices and prices
- Detail view with a timeline, expandable intermediate stops and transfer wait times. It also has
  a map showing the real route shapes and live vehicle positions, plus a ticket purchase link and
  sharing. Live data refreshes every 30 s.
- A departure board for any stop, with a line filter and auto-refresh
- Favorite and recent routes and stops
- iPad: split view, with results in the sidebar and the detail and map side by side

## Backend API (unofficial, reverse-engineered)

Base URL: `https://jizdnirady.seznam.cz`. The web app sends binary FastRPC, but the server also
speaks plain **XML-RPC**, which is what `API/RPCValue.swift` implements.

| Call | Purpose |
|---|---|
| `GET /suggest?phrase=…&type=municipality\|address\|poi\|area\|firm\|pubt` | Place autocomplete (JSON) |
| `POST /routept/` `getRoutesOpt(date, isDeparture, {start,end,mid,index,count}, options)` | Connections. A negative `index` returns earlier ones |
| `getTripInfo([{tripId: partDescription, time}])` | Live info: delay (s), platforms (code 400), predictions (500), notices |
| `getTripDetail(partDescription, {startindex,endindex,time})` | Trip stops and geometry (`geom` = the ridden part) |
| `getWalkGeom({start:{x,y}, end:{x,y}})` | Walking geometry |
| `getStopDepartures(date, {start,end,mid,index,count}, {version:3})` | Departure board (not used by the website) |

Geometry strings use Mapy.cz's compact polyline encoding (see `API/GeometryDecoder.swift`).
Because this API is undocumented, it may change without notice.
