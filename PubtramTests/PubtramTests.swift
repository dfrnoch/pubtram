import Foundation
import Testing

@testable import Pubtram

struct GeometryDecoderTests {
    @Test func decodesMapyCzPolyline() {
        // Real geometry from getTripDetail, starting at Praha hlavní nádraží.
        let coords = GeometryDecoder.decode("9hCnPxXvmiKpHyHxflxLQIXLnJ8LsKCLhJ8LLJ1KvIzJH4vE6DsI14gE62GKD")
        #expect(coords.count > 5)
        #expect(abs(coords[0].longitude - 14.434687) < 0.00001)
        #expect(abs(coords[0].latitude - 50.083222) < 0.00001)
        #expect(abs(coords[1].longitude - 14.434498) < 0.00001)
    }

    @Test func emptyInput() {
        #expect(GeometryDecoder.decode("").isEmpty)
    }
}

struct XMLRPCTests {
    @Test func encodesNestedStructsAndDates() throws {
        let date = try #require(RPCDate.parseISO("2026-10-15T08:00:00+02:00"))
        let data = XMLRPCEncoder.methodCall("getRoutesOpt", params: [.date(date), true, ["x": 14.5, "name": "A&B"]])
        let xml = try #require(String(data: data, encoding: .utf8))
        #expect(xml.contains("<methodName>getRoutesOpt</methodName>"))
        #expect(xml.contains("<dateTime.iso8601>20261015T08:00:00</dateTime.iso8601>"))
        #expect(xml.contains("<boolean>1</boolean>"))
        #expect(xml.contains("<name>name</name><value><string>A&amp;B</string></value>"))
        #expect(xml.contains("<double>14.5</double>"))
    }

    @Test func decodesResponse() throws {
        let xml = """
            <?xml version="1.0"?>
            <methodResponse><params><param><value><struct>
            <member><name>status</name><value><i4>200</i4></value></member>
            <member><name>ok</name><value><boolean>1</boolean></value></member>
            <member><name>plain</name><value>untyped</value></member>
            <member><name>empty</name><value><string></string></value></member>
            <member><name>list</name><value><array><data>
              <value><double>1.5</double></value>
              <value><struct><member><name>n</name><value><string>Hlavní nádraží</string></value></member></struct></value>
            </data></array></value></member>
            </struct></value></param></params></methodResponse>
            """
        let value = try XMLRPCDecoder.decode(Data(xml.utf8))
        #expect(value["status"]?.int == 200)
        #expect(value["ok"]?.bool == true)
        #expect(value["plain"]?.string == "untyped")
        #expect(value["empty"]?.string == "")
        #expect(value["list"]?.array.count == 2)
        #expect(value["list"]?.array[0].double == 1.5)
        #expect(value["list"]?.array[1]["n"]?.string == "Hlavní nádraží")
    }

    @Test func decodesFault() {
        let xml = """
            <?xml version="1.0"?><methodResponse><fault><value><struct>
            <member><name>faultCode</name><value><i4>-506</i4></value></member>
            <member><name>faultString</name><value><string>Method not found</string></value></member>
            </struct></value></fault></methodResponse>
            """
        #expect(throws: RPCFault.self) { try XMLRPCDecoder.decode(Data(xml.utf8)) }
    }
}

struct ResponseParserTests {
    private func routeResponse() -> RPCValue {
        let t = { (s: String) in RPCValue.string("2026-10-15T08:\(s):00+02:00") }
        return [
            "status": 200,
            "agenciesinfo": [["name": "PID", "short_name": ""]],
            "hashes": [42],
            "stops": [
                ["id": 1, "name": "Florenc", "coord": [14.44, 50.09]],
                ["id": 2, "name": "Hlavní nádraží", "coord": [14.43, 50.08]],
                ["id": 3, "name": "Muzeum", "coord": [14.43, 50.07], "parent_id": 33],
            ],
            "routes": [
                [
                    "hash": 42, "departureISO": t("01"), "arrivalISO": t("10"), "transferCount": 0,
                    "startPos": [14.43, 50.08], "endPos": [14.43, 50.07],
                    "payment": [["type": "price", "price": 36.0, "currency_type": "CZK", "eshopName": "Lítačka"]],
                    "items": [
                        [
                            "type": 0, "vehicleType": 4, "routeName": "C", "agencyIndex": 0,
                            "partDescription": "L993;;x", "tripID": 7,
                            "departureISO": t("02"), "arrivalISO": t("04"),
                            "startStopTripIndex": 1, "endStopTripIndex": 2,
                            "info": [
                                ["id": 15, "text": ""],
                                ["id": 302, "delay": 180, "text": "Zpoždění 3 min"],
                                ["id": 500, "stopID": 33, "delay": 240, "text": ""],
                                ["id": 400, "stopID": 2, "text": " 1   / 2 "],
                                ["id": 202, "text": "Výluka", "url": "https://example.com"],
                            ],
                            "tripData": [
                                ["stopIndex": 0, "departureISO": t("00"), "arrivalISO": t("00"), "stCodes": []],
                                ["stopIndex": 1, "departureISO": t("02"), "arrivalISO": t("02"), "stCodes": [["id": 7, "text": "P"]]],
                                ["stopIndex": 2, "departureISO": t("04"), "arrivalISO": t("04"), "stCodes": [["id": 28, "text": ""]]],
                            ],
                        ],
                        [
                            "type": 1, "distance": 250, "departureISO": t("04"), "arrivalISO": t("10"),
                            "oznStartCoord": [14.43, 50.07], "oznEndCoord": [14.42, 50.07],
                        ],
                    ],
                ]
            ],
        ]
    }

    @Test func parsesConnection() throws {
        let connections = ResponseParser.connections(routeResponse())
        let c = try #require(connections.first)
        #expect(c.id == 42)
        #expect(c.legs.count == 2)
        #expect(c.prices.first?.amount == 36)
        #expect(c.duration == 9 * 60)

        let ride = try #require(c.firstRide)
        #expect(ride.vehicle == .metro)
        #expect(ride.line == "C")
        #expect(ride.agency == "PID")
        #expect(ride.direction == "Muzeum")
        #expect(ride.boardStop?.name == "Hlavní nádraží")
        #expect(ride.boardStop?.zone == "P")
        #expect(ride.alightStop?.onRequest == true)
        #expect(ride.delay == 180)
        #expect(ride.delay(at: ride.alightStop!) == 240)
        #expect(ride.boardPlatform == "1 / 2")
        #expect(ride.features.contains(.lowFloor))
        #expect(ride.notices.first?.text == "Výluka")
        #expect(ride.intermediateStopCount == 0)

        guard case .walk(let walk) = c.legs[1] else {
            Issue.record("expected walk leg")
            return
        }
        #expect(walk.distance == 250)
    }

    @Test func liveInfoMergeKeepsExistingValues() throws {
        let ride = try #require(ResponseParser.connections(routeResponse()).first?.firstRide)
        let updated = ride.applying(ResponseParser.liveInfo([["id": 300, "delay": 0, "text": "Bez zpoždění"]]))
        #expect(updated.delay == 0)
        #expect(updated.boardPlatform == "1 / 2")
        #expect(updated.notices.count == 1)
    }
}

struct FormattingTests {
    @Test func platformLabels() {
        #expect(Platform.normalize(" 5   / -") == "5 / -")
        #expect(Platform.normalize("- / -") == nil)
        #expect(Platform.label("4 / 14") == "nást. 4 · kol. 14")
        #expect(Platform.label("- / 8") == "kol. 8")
        #expect(Platform.label("5 / -") == "nást. 5")
        #expect(Platform.label("D") == "stan. D")
    }

    @Test func czechPlurals() {
        #expect(Fmt.transfers(0) == "přímé")
        #expect(Fmt.transfers(3) == "3 přestupy")
        #expect(Fmt.transfers(5) == "5 přestupů")
        #expect(Fmt.stops(1) == "1 zastávka")
        #expect(Fmt.stops(4) == "4 zastávky")
        #expect(Fmt.stops(12) == "12 zastávek")
    }

    @Test func durations() {
        #expect(Fmt.duration(16 * 60) == "16 min")
        #expect(Fmt.duration(2 * 3600) == "2 h")
        #expect(Fmt.duration(161 * 60) == "2 h 41 min")
        #expect(Fmt.delayMinutes(2160) == 36)
        #expect(Fmt.delayMinutes(-60) == 0)
    }
}
