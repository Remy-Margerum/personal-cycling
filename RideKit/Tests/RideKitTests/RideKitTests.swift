import XCTest
#if canImport(FoundationXML)
import FoundationXML // XMLParser lives here on Linux
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking // URLRequest lives here on Linux
#endif
@testable import RideKit

final class CyclingPowerMeasurementTests: XCTestCase {
    func testPowerOnly() throws {
        let m = try XCTUnwrap(CyclingPowerMeasurement(data: [0x00, 0x00, 0xFA, 0x00]))
        XCTAssertEqual(m.instantaneousPower, 250)
        XCTAssertNil(m.crank)
        XCTAssertNil(m.pedalPowerBalance)
    }

    func testBalanceAndCrankData() throws {
        // flags 0x0023: balance present, reference left, crank data present
        // power 300 W, balance 0x64 = 50.0 %, revs 0x0102, time 0x0400 (1 s)
        let bytes: [UInt8] = [0x23, 0x00, 0x2C, 0x01, 0x64, 0x02, 0x01, 0x00, 0x04]
        let m = try XCTUnwrap(CyclingPowerMeasurement(data: bytes))
        XCTAssertEqual(m.instantaneousPower, 300)
        XCTAssertEqual(m.pedalPowerBalance, 50.0)
        XCTAssertTrue(m.flags.contains(.pedalPowerBalanceReferenceLeft))
        XCTAssertEqual(m.crank, .init(cumulativeRevolutions: 0x0102, lastEventTime: 0x0400))
    }

    func testCrankDataAfterTorqueAndWheelFields() throws {
        // flags 0x0034: accumulated torque + wheel data + crank data
        let bytes: [UInt8] = [0x34, 0x00, 0x64, 0x00,
                              0xAA, 0xBB,                         // torque (skipped)
                              0x01, 0x02, 0x03, 0x04, 0x05, 0x06, // wheel (skipped)
                              0x0A, 0x00, 0x00, 0x08]             // crank
        let m = try XCTUnwrap(CyclingPowerMeasurement(data: bytes))
        XCTAssertEqual(m.instantaneousPower, 100)
        XCTAssertEqual(m.crank, .init(cumulativeRevolutions: 10, lastEventTime: 0x0800))
    }

    func testNegativePowerIsSigned() throws {
        let m = try XCTUnwrap(CyclingPowerMeasurement(data: [0x00, 0x00, 0xFF, 0xFF]))
        XCTAssertEqual(m.instantaneousPower, -1)
    }

    func testTruncatedPacketIsRejected() {
        XCTAssertNil(CyclingPowerMeasurement(data: [0x00]))
        XCTAssertNil(CyclingPowerMeasurement(data: [0x20, 0x00, 0x64, 0x00, 0x01]))
    }

    func testBatteryLevel() {
        XCTAssertEqual(parseBatteryLevel([87]), 87)
        XCTAssertNil(parseBatteryLevel([]))
        XCTAssertNil(parseBatteryLevel([200]))
    }
}

final class CadenceCalculatorTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testNinetyRPM() {
        var calc = CadenceCalculator()
        calc.update(.init(cumulativeRevolutions: 100, lastEventTime: 0), receivedAt: t0)
        // 3 revolutions in 2 s (2048 ticks) = 90 rpm
        let rpm = calc.update(.init(cumulativeRevolutions: 103, lastEventTime: 2048), receivedAt: t0 + 2)
        XCTAssertEqual(try XCTUnwrap(rpm), 90, accuracy: 0.001)
    }

    func testCounterRollover() {
        var calc = CadenceCalculator()
        calc.update(.init(cumulativeRevolutions: 65_535, lastEventTime: 65_000), receivedAt: t0)
        // 1 revolution, 683 ticks across the time wrap ≈ 89.96 rpm
        let rpm = calc.update(.init(cumulativeRevolutions: 0, lastEventTime: 147), receivedAt: t0 + 1)
        XCTAssertEqual(try XCTUnwrap(rpm), 60 * 1024 / 683, accuracy: 0.01)
    }

    func testRepeatedReadingKeepsCadenceThenDropsToZero() {
        var calc = CadenceCalculator(stopTimeout: 3)
        calc.update(.init(cumulativeRevolutions: 1, lastEventTime: 0), receivedAt: t0)
        calc.update(.init(cumulativeRevolutions: 2, lastEventTime: 1024), receivedAt: t0 + 1)
        XCTAssertEqual(calc.update(.init(cumulativeRevolutions: 2, lastEventTime: 1024), receivedAt: t0 + 2), 60)
        XCTAssertEqual(calc.update(.init(cumulativeRevolutions: 2, lastEventTime: 1024), receivedAt: t0 + 4.5), 0)
    }

    func testExpireIfStale() {
        var calc = CadenceCalculator(stopTimeout: 3)
        calc.update(.init(cumulativeRevolutions: 1, lastEventTime: 0), receivedAt: t0)
        calc.update(.init(cumulativeRevolutions: 2, lastEventTime: 1024), receivedAt: t0 + 1)
        calc.expireIfStale(now: t0 + 2)
        XCTAssertEqual(calc.cadence, 60)
        calc.expireIfStale(now: t0 + 5)
        XCTAssertEqual(calc.cadence, 0)
    }

    func testImplausibleValueIgnored() {
        var calc = CadenceCalculator()
        calc.update(.init(cumulativeRevolutions: 1, lastEventTime: 0), receivedAt: t0)
        calc.update(.init(cumulativeRevolutions: 2, lastEventTime: 1024), receivedAt: t0 + 1)
        calc.update(.init(cumulativeRevolutions: 50, lastEventTime: 2048), receivedAt: t0 + 2)
        XCTAssertEqual(calc.cadence, 60)
    }
}

final class RideMetricsTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testHaversineOneDegreeOfLatitude() {
        XCTAssertEqual(haversineDistance(lat1: 0, lon1: 0, lat2: 1, lon2: 0), 111_195, accuracy: 10)
    }

    func testDistanceAccumulatorFiltersBadFixes() {
        var acc = DistanceAccumulator()
        // ~0.0001° latitude ≈ 11.1 m per step
        acc.add(LocationFix(timestamp: t0, latitude: 34.4, longitude: -119.7, horizontalAccuracy: 5, speed: 10))
        acc.add(LocationFix(timestamp: t0 + 1, latitude: 34.4001, longitude: -119.7, horizontalAccuracy: 5, speed: 10))
        XCTAssertEqual(acc.total, 11.1, accuracy: 0.1)

        // Poor accuracy: rejected
        XCTAssertFalse(acc.add(LocationFix(timestamp: t0 + 2, latitude: 34.5, longitude: -119.7, horizontalAccuracy: 65, speed: 10)))
        // Teleport (~1 km in 1 s): rejected
        XCTAssertFalse(acc.add(LocationFix(timestamp: t0 + 3, latitude: 34.41, longitude: -119.7, horizontalAccuracy: 5, speed: 10)))
        // Stationary jitter: accepted but not counted
        acc.add(LocationFix(timestamp: t0 + 4, latitude: 34.40012, longitude: -119.7, horizontalAccuracy: 5, speed: 0))
        XCTAssertEqual(acc.total, 11.1, accuracy: 0.1)
    }

    func testBreakSegmentSkipsGap() {
        var acc = DistanceAccumulator()
        acc.add(LocationFix(timestamp: t0, latitude: 34.4, longitude: -119.7, horizontalAccuracy: 5, speed: 5))
        acc.breakSegment()
        acc.add(LocationFix(timestamp: t0 + 600, latitude: 34.45, longitude: -119.7, horizontalAccuracy: 5, speed: 5))
        XCTAssertEqual(acc.total, 0)
    }

    func testElevationHysteresis() {
        var elev = ElevationGainAccumulator(threshold: 1)
        for alt in [100.0, 100.4, 99.8, 100.3, 101.2, 102.5, 102.1, 104.0, 103.0] {
            elev.add(altitude: alt)
        }
        // Counted: 100 → 101.2 → 102.5 → 104.0; the 0.4 m wobbles are ignored.
        XCTAssertEqual(elev.gain, 4.0, accuracy: 0.001)
        XCTAssertEqual(elev.loss, 1.0, accuracy: 0.001)
    }

    func testRollingAverage() {
        var avg = RollingAverage(window: 3)
        avg.add(100, at: t0)
        avg.add(200, at: t0 + 1)
        avg.add(300, at: t0 + 2)
        avg.add(400, at: t0 + 4)
        XCTAssertEqual(avg.average, 300) // 100 W (4 s old) has dropped out
    }
}

final class RideSummaryAndTCXTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_758_800_000)

    func makeRide() -> Ride {
        let samples = (0..<60).map { (i: Int) -> RideSample in
            let x = Double(i)
            let power: Int = i < 30 ? 100 : 300
            let cadence: Int = i == 0 ? 0 : 90
            return RideSample(timestamp: t0.addingTimeInterval(x), latitude: 34.4 + x * 0.0001, longitude: -119.7,
                              altitude: 10 + x * 0.1, distance: x * 11.1, speed: 11.1,
                              heartRate: 140 + i % 10, power: power, cadence: cadence)
        }
        return Ride(startDate: t0, endDate: t0 + 59, movingTime: 59, elevationGain: 5.9, samples: samples)
    }

    func testSummary() throws {
        let s = makeRide().summary
        XCTAssertEqual(s.distance, 59 * 11.1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.averagePower), 200, accuracy: 0.001)
        XCTAssertEqual(s.maxPower, 300)
        XCTAssertEqual(s.maxHeartRate, 149)
        XCTAssertEqual(try XCTUnwrap(s.averageCadence), 90, accuracy: 0.001) // leading zero excluded
        // NP of a 100 W → 300 W step is above the 200 W average
        XCTAssertGreaterThan(try XCTUnwrap(s.normalizedPower), 200)
    }

    func testNormalizedPowerOfSteadyEffortEqualsAverage() throws {
        XCTAssertEqual(try XCTUnwrap(RideSummary.normalizedPower(Array(repeating: 250, count: 120))), 250, accuracy: 0.001)
        XCTAssertNil(RideSummary.normalizedPower([250, 250]))
    }

    func testBuckets() throws {
        let ride = makeRide()
        let buckets = ride.buckets(seconds: 5)
        XCTAssertEqual(buckets.count, 12)
        XCTAssertEqual(buckets[0].start, t0)
        XCTAssertEqual(buckets[0].end, t0 + 5)
        XCTAssertEqual(try XCTUnwrap(buckets[0].averagePower), 100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(buckets[0].averageCadence), 90, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(buckets[11].averagePower), 300, accuracy: 0.001)
        // Bucket distances add back up to the ride's total.
        XCTAssertEqual(buckets.map(\.distance).reduce(0, +), ride.summary.distance, accuracy: 0.001)
    }

    func testTCXContainsAllChannelsAndParses() throws {
        let xml = TCXWriter.tcx(for: makeRide())
        XCTAssertTrue(xml.contains(#"<Activity Sport="Biking">"#))
        XCTAssertTrue(xml.contains("<Id>2025-09-25T11:33:20Z</Id>"))
        XCTAssertTrue(xml.contains("<LatitudeDegrees>34.4000000</LatitudeDegrees>"))
        XCTAssertTrue(xml.contains("<HeartRateBpm><Value>140</Value></HeartRateBpm>"))
        XCTAssertTrue(xml.contains("<Cadence>90</Cadence>"))
        XCTAssertTrue(xml.contains("<ns3:Watts>300</ns3:Watts>"))
        XCTAssertEqual(xml.components(separatedBy: "<Trackpoint>").count - 1, 60)

        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), "TCX is not well-formed XML: \(String(describing: parser.parserError))")
    }
}

final class DebugFormatTests: XCTestCase {
    func testHex() {
        XCTAssertEqual(DebugFormat.hex([0x23, 0x00, 0x2C, 0x01, 0xFF]), "23 00 2C 01 FF")
        XCTAssertEqual(DebugFormat.hex([]), "")
    }

    func testDescribePowerPacket() throws {
        let bytes: [UInt8] = [0x23, 0x00, 0x2C, 0x01, 0x64, 0x02, 0x01, 0x00, 0x04]
        let m = try XCTUnwrap(CyclingPowerMeasurement(data: bytes))
        XCTAssertEqual(DebugFormat.describe(m), "flags=0x0023 power=300W balance=50.0%L crank=258/1024")
        let powerOnly = try XCTUnwrap(CyclingPowerMeasurement(data: [0x00, 0x00, 0xFA, 0x00]))
        XCTAssertEqual(DebugFormat.describe(powerOnly), "flags=0x0000 power=250W crank=none")
    }

    func testLine() {
        let date = Date(timeIntervalSince1970: 3_600 * 14 + 60 * 3 + 7.25)
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(DebugFormat.line(date: date, category: "power", message: "hi", timeZone: utc),
                       "14:03:07.250 [power] hi")
    }

    func testFixed() {
        XCTAssertEqual(DebugFormat.fixed(5.216, 2), "5.22")
        XCTAssertEqual(DebugFormat.fixed(nil, 1), "--")
        XCTAssertEqual(DebugFormat.fixed(.nan, 1), "--")
    }

    func testLogRingKeepsNewestLines() {
        var ring = LogRing(capacity: 4)
        for i in 1...20 { ring.append("\(i)") }
        XCTAssertEqual(ring.lines, ["17", "18", "19", "20"])
        ring.append("21")
        XCTAssertEqual(ring.lines, ["18", "19", "20", "21"])
        ring.removeAll()
        XCTAssertEqual(ring.lines, [])
    }
}

final class ActiveLookTests: XCTestCase {
    private func hex(_ string: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            bytes.append(UInt8(string[index ..< next], radix: 16)!)
            index = next
        }
        return bytes
    }

    func testFramesMatchTheAPIDocumentExamples() {
        // "clear": 0xFF 0x01 0x00 0x05 0xAA
        XCTAssertEqual(ActiveLook.Command.clear.frame, [0xFF, 0x01, 0x00, 0x05, 0xAA])
        // "display text `hello 4` at (152;128) with direction 4, the font 2 and the color 15"
        XCTAssertEqual(ActiveLook.Command.text(x: 152, y: 128, rotation: 4, font: 2, grey: 15, "hello 4").frame,
                       hex("FF3700140098008004020F68656C6C6F203400AA"))
    }

    func testConfigurationAndLayoutFrames() {
        XCTAssertEqual(ActiveLook.Command.configurationSet("ALooK").frame,
                       [0xFF, 0xD2, 0x00, 0x0B, 0x41, 0x4C, 0x6F, 0x6F, 0x4B, 0x00, 0xAA])
        // layout 113 at x 30, y 149, text "&$245"
        XCTAssertEqual(ActiveLook.Command.layoutClearAndDisplay(id: 113, x: 30, y: 149, text: "&$245").frame,
                       [0xFF, 0x6A, 0x00, 0x0F, 0x71, 0x00, 0x1E, 0x95, 0x26, 0x24, 0x32, 0x34, 0x35, 0x00, 0xAA])
        // Non-ASCII characters are dropped.
        XCTAssertEqual(ActiveLook.Command.configurationRead("ALooK°").frame,
                       ActiveLook.Command.configurationRead("ALooK").frame)
    }

    func testLongFrameUsesTwoByteLength() {
        let frame = ActiveLook.Command.text(x: 0, y: 0, rotation: 4, font: 1, grey: 15,
                                            String(repeating: "x", count: 300)).frame
        // 7 bytes of parameters + 300 characters + NUL + 6 bytes of framing = 314
        XCTAssertEqual(Array(frame.prefix(5)), [0xFF, 0x37, 0x10, 0x01, 0x3A])
        XCTAssertEqual(frame.count, 314)
        XCTAssertEqual(frame.last, 0xAA)
    }

    func testResponseReaderReassemblesSplitFrames() {
        var reader = ActiveLook.ResponseReader()
        // version 4.11.2b, split across two notifications
        let version: [UInt8] = [0xFF, 0x06, 0x00, 0x0E, 0x04, 0x0B, 0x02, 0x62, 0x1A, 0x05, 0x00, 0x00, 0x02, 0xAA]
        let partial = reader.append(Array(version.prefix(6)))
        XCTAssertEqual(partial, [])
        let responses = reader.append(Array(version.dropFirst(6)))
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.version, "4.11.2b")
    }

    func testResponseReaderHandlesJoinedFramesQueryIDsAndGarbage() {
        var reader = ActiveLook.ResponseReader()
        let battery: [UInt8] = [0xFF, 0x05, 0x00, 0x06, 0x57, 0xAA]                 // 87 %
        let withQueryID: [UInt8] = [0xFF, 0x05, 0x02, 0x08, 0x01, 0x02, 0x64, 0xAA] // query id 2 bytes, 100 %
        let responses = reader.append([0x12, 0x34] + battery + withQueryID)
        XCTAssertEqual(responses.map(\.batteryLevel), [87, 100])

        let error: [UInt8] = [0xFF, 0xE2, 0x00, 0x08, 0xD2, 0x02, 0x00, 0xAA]
        let parsed = reader.append(error)
        XCTAssertEqual(parsed.first?.error?.command, 0xD2)
        XCTAssertEqual(parsed.first?.error?.code, 2)
    }

    func testConfigurationReadResponse() {
        let response = ActiveLook.Response(id: 0xD1, data: [0, 0, 0, 11, 120, 185, 5, 0, 0])
        XCTAssertEqual(response.configurationLayoutCount, 185)
    }

    func testControlSignals() {
        XCTAssertEqual(ActiveLook.ControlSignal([0x01]), .resume)
        XCTAssertEqual(ActiveLook.ControlSignal([0x02]), .pause)
        XCTAssertEqual(ActiveLook.ControlSignal([0x03]), .error(0x03))
        XCTAssertNil(ActiveLook.ControlSignal([]))
    }

    func testAdvertisementFilter() {
        XCTAssertTrue(ActiveLook.isActiveLook(manufacturerData: [0xFA, 0xDA, 0x08, 0xF2]))
        XCTAssertFalse(ActiveLook.isActiveLook(manufacturerData: [0x4C, 0x00, 0x02, 0x15]))
        XCTAssertFalse(ActiveLook.isActiveLook(manufacturerData: [0x08, 0xF2]))
        // Without the marker, known names still match, in any case.
        XCTAssertTrue(ActiveLook.isActiveLook(manufacturerData: [], name: "engo3 123456"))
        XCTAssertTrue(ActiveLook.isActiveLook(manufacturerData: [], name: "ENGO 2 004321"))
        XCTAssertTrue(ActiveLook.isActiveLook(manufacturerData: [], name: "A.LooK  000128"))
        XCTAssertFalse(ActiveLook.isActiveLook(manufacturerData: [], name: "Wahoo TICKR"))
        XCTAssertFalse(ActiveLook.isActiveLook(manufacturerData: [], name: nil))
    }

    func testQueueSendsOneWriteAtATimeAndChunks() {
        var queue = ActiveLook.CommandQueue()
        queue.enqueue(.clear)
        queue.enqueue(.configurationSet("ALooK"))
        XCTAssertEqual(queue.nextWrite(maxLength: 20), [0xFF, 0x01, 0x00, 0x05, 0xAA])
        XCTAssertNil(queue.nextWrite(maxLength: 20), "waits for the write to be acknowledged")
        queue.acknowledged()
        // 11-byte frame in 4-byte chunks
        var chunks: [[UInt8]] = []
        while let chunk = queue.nextWrite(maxLength: 4) {
            chunks.append(chunk)
            queue.acknowledged()
        }
        XCTAssertEqual(chunks.map(\.count), [4, 4, 3])
        XCTAssertEqual(chunks.flatMap { $0 }, ActiveLook.Command.configurationSet("ALooK").frame)
        XCTAssertTrue(queue.isEmpty)
    }

    func testQueueReplacesStaleValuesInPlace() {
        var queue = ActiveLook.CommandQueue()
        queue.enqueue(.layoutClearAndDisplay(id: 113, x: 30, y: 149, text: "&$200"), key: "power")
        queue.enqueue(.layoutClearAndDisplay(id: 83, x: 30, y: 80, text: "&$140"), key: "hr")
        queue.enqueue(.layoutClearAndDisplay(id: 113, x: 30, y: 149, text: "&$250"), key: "power")
        var frames: [[UInt8]] = []
        while let frame = queue.nextWrite(maxLength: 512) {
            frames.append(frame)
            queue.acknowledged()
        }
        XCTAssertEqual(frames, [
            ActiveLook.Command.layoutClearAndDisplay(id: 113, x: 30, y: 149, text: "&$250").frame,
            ActiveLook.Command.layoutClearAndDisplay(id: 83, x: 30, y: 80, text: "&$140").frame,
        ])
    }

    func testAlignmentFollowsTheGhostCharacterExamples() {
        // From the ActiveLook visual assets README.
        XCTAssertEqual(GlassesDashboard.aligned("123"), "&$123")
        XCTAssertEqual(GlassesDashboard.aligned("1"), "&$$$1")
        XCTAssertEqual(GlassesDashboard.aligned("00:00"), "00:00")
        XCTAssertEqual(GlassesDashboard.aligned("18.4"), "$18.4")
        XCTAssertEqual(GlassesDashboard.aligned("--"), "&$$--")
    }

    func testDashboardFields() {
        let metrics = GlassesMetrics(power3s: 244.6, heartRate: 142, speed: 8.23, cadence: 88.4, metric: false)
        let fields = GlassesDashboard.fields(metrics)
        XCTAssertEqual(fields.map { $0.field }, [GlassesDashboard.power, GlassesDashboard.heartRate,
                                                 GlassesDashboard.speed, GlassesDashboard.cadence])
        XCTAssertEqual(fields.map { $0.text }, ["&$245", "&$142", "$18.4", "&$$88"]) // 8.23 m/s = 18.4 mph

        var metricUnits = metrics
        metricUnits.metric = true
        XCTAssertEqual(GlassesDashboard.fields(metricUnits)[2].text, "$29.6") // km/h

        XCTAssertEqual(GlassesDashboard.fields(GlassesMetrics()).map { $0.text }, ["&$$--", "&$$--", "&$$--", "&$$--"])
    }
}

final class IntervalsTests: XCTestCase {
    func testUploadRequest() throws {
        let file = Data("<TrainingCenterDatabase/>".utf8)
        let request = Intervals.uploadRequest(file: file, filename: "ride.tcx", name: "Raggio ride",
                                              externalID: "ABC-123", apiKey: "secret", boundary: "B")
        XCTAssertEqual(request.httpMethod, "POST")
        let url = try XCTUnwrap(request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.path, "/api/v1/athlete/0/activities")
        XCTAssertEqual(query.first { $0.name == "name" }?.value, "Raggio ride")
        XCTAssertEqual(query.first { $0.name == "device_name" }?.value, "Raggio (iPhone)")
        XCTAssertEqual(query.first { $0.name == "external_id" }?.value, "ABC-123")
        // Basic auth, user "API_KEY": base64("API_KEY:secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic QVBJX0tFWTpzZWNyZXQ=")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=B")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertEqual(body, "--B\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"ride.tcx\"\r\n"
            + "Content-Type: application/vnd.garmin.tcx+xml\r\n\r\n"
            + "<TrainingCenterDatabase/>\r\n--B--\r\n")
    }

    func testOutcomes() throws {
        let json = Data(#"{"icu_athlete_id":"i1","id":"i1","activities":[{"icu_athlete_id":"i1","id":"i98765"}]}"#.utf8)
        XCTAssertEqual(try Intervals.outcome(status: 201, body: json), .created(activityID: "i98765"))
        XCTAssertEqual(try Intervals.outcome(status: 200, body: json), .duplicate(activityID: "i98765"))
        XCTAssertEqual(try Intervals.outcome(status: 201, body: Data("not json".utf8)), .created(activityID: nil))
        XCTAssertThrowsError(try Intervals.outcome(status: 401, body: Data())) {
            XCTAssertEqual($0 as? Intervals.UploadError, .unauthorized)
        }
        XCTAssertThrowsError(try Intervals.outcome(status: 422, body: Data("bad file".utf8))) {
            XCTAssertEqual($0 as? Intervals.UploadError, .rejected(status: 422, message: "bad file"))
        }
        XCTAssertThrowsError(try Intervals.outcome(status: 503, body: Data())) {
            XCTAssertEqual($0 as? Intervals.UploadError, .unavailable(status: 503))
        }
        XCTAssertEqual(Intervals.activityURL("i98765")?.absoluteString, "https://intervals.icu/activities/i98765")
    }

    func testUploadLog() throws {
        let old = UUID(), first = UUID(), second = UUID()
        var log = Intervals.UploadLog()
        log.queue(first)
        log.queue(second)
        // Rides never queued (e.g. saved before auto-upload) are left alone.
        XCTAssertEqual(log.pending(among: [old, first, second]), [first, second])

        log.record(.failed("offline"), for: first)
        log.record(.uploaded(activityID: "i1", at: Date(timeIntervalSince1970: 0)), for: second)
        XCTAssertEqual(log.pending(among: [old, first, second]), [first], "failed uploads are retried")
        log.queue(second)
        XCTAssertEqual(log[second], .uploaded(activityID: "i1", at: Date(timeIntervalSince1970: 0)),
                       "queueing an uploaded ride doesn't upload it again")
        log.queue(first)
        XCTAssertEqual(log[first], .failed("offline"), "queueing keeps the last error until the retry")

        let decoded = try JSONDecoder().decode(Intervals.UploadLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(decoded, log)
    }
}
