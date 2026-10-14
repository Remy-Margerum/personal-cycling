import Foundation

/// A point on the winery floor, in meters from its top-left corner (x to the
/// right, y towards the roll-up door). Also used as a direction.
public struct FloorPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = FloorPoint(0, 0)

    public static func + (a: FloorPoint, b: FloorPoint) -> FloorPoint { FloorPoint(a.x + b.x, a.y + b.y) }
    public static func - (a: FloorPoint, b: FloorPoint) -> FloorPoint { FloorPoint(a.x - b.x, a.y - b.y) }
    public static func * (a: FloorPoint, k: Double) -> FloorPoint { FloorPoint(a.x * k, a.y * k) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: FloorPoint) -> Double { (self - other).length }
}

/// A rectangle on the floor, in meters.
public struct FloorRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var center: FloorPoint { FloorPoint(x + width / 2, y + height / 2) }

    /// Grown by `amount` on every side (shrunk if it's negative).
    public func grown(by amount: Double) -> FloorRect {
        FloorRect(x: x - amount, y: y - amount, width: width + 2 * amount, height: height + 2 * amount)
    }

    public func contains(_ p: FloorPoint) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    /// How far a point is from the rectangle; 0 inside it.
    public func distance(to p: FloorPoint) -> Double {
        let dx = Swift.max(minX - p.x, 0, p.x - maxX)
        let dy = Swift.max(minY - p.y, 0, p.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// The machines and vessels on the winery floor.
public enum StationID: String, Codable, CaseIterable, Sendable, Identifiable {
    case bins, destemmer, press, fermenter, steelTank, barrels, newBarrels, chiller, lab

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .bins: "Picking bins"
        case .destemmer: "Destemmer"
        case .press: "Press"
        case .fermenter: "Fermenter"
        case .steelTank: "Steel tank"
        case .barrels: "Neutral barrels"
        case .newBarrels: "New French oak"
        case .chiller: "Chiller"
        case .lab: "Lab bench"
        }
    }

    /// The vessel it is, for the ones wine can go into.
    public var vessel: Vessel? {
        switch self {
        case .steelTank: .stainless
        case .barrels: .neutralOak
        case .newBarrels: .newOak
        case .bins, .destemmer, .press, .fermenter, .chiller, .lab: nil
        }
    }
}

/// Where a station stands, and how big it's drawn.
public struct Station: Equatable, Sendable, Identifiable {
    public let id: StationID
    /// The base of the machine on the floor. Doug walks around it.
    public let footprint: FloorRect
    /// The drawing's width in meters, centered on the footprint and standing
    /// on its bottom edge. Its height follows from the artwork.
    public let drawWidth: Double
}

/// The winery floor: a 9 m by 13.4 m room, back wall at the top and the
/// roll-up door to the crush pad at the bottom. Doug walks it in both the
/// crush and the cellar.
public enum Floor {
    public static let width = 9.0
    public static let height = 13.4
    /// The back wall: nobody walks here.
    public static let wall = 1.4
    /// Where Doug comes in, by the door.
    public static let start = FloorPoint(7.6, 12.4)
    /// How close Doug has to be to work a station.
    public static let reach = 0.7

    public static let stations: [Station] = [
        Station(id: .barrels, footprint: FloorRect(x: 0.4, y: 1.7, width: 3.0, height: 1.2), drawWidth: 3.0),
        Station(id: .newBarrels, footprint: FloorRect(x: 4.4, y: 1.6, width: 1.8, height: 1.2), drawWidth: 2.0),
        Station(id: .steelTank, footprint: FloorRect(x: 6.9, y: 1.8, width: 1.8, height: 1.4), drawWidth: 1.7),
        Station(id: .lab, footprint: FloorRect(x: 0.3, y: 4.6, width: 2.2, height: 1.0), drawWidth: 2.3),
        Station(id: .chiller, footprint: FloorRect(x: 7.3, y: 4.4, width: 1.4, height: 0.9), drawWidth: 1.5),
        Station(id: .fermenter, footprint: FloorRect(x: 1.2, y: 7.6, width: 2.2, height: 1.5), drawWidth: 2.3),
        Station(id: .press, footprint: FloorRect(x: 4.6, y: 7.9, width: 3.5, height: 1.2), drawWidth: 3.6),
        Station(id: .bins, footprint: FloorRect(x: 0.4, y: 11.0, width: 2.4, height: 1.2), drawWidth: 2.5),
        Station(id: .destemmer, footprint: FloorRect(x: 4.0, y: 10.9, width: 1.9, height: 1.2), drawWidth: 2.1),
    ]

    public static func station(_ id: StationID) -> Station {
        stations.first { $0.id == id } ?? stations[0]
    }

    /// The station Doug is close enough to work, nearest first.
    public static func station(near p: FloorPoint) -> StationID? {
        stations
            .map { (id: $0.id, distance: $0.footprint.distance(to: p)) }
            .filter { $0.distance <= reach }
            .min { $0.distance < $1.distance }?
            .id
    }

    /// Whether Doug (a circle `radius` wide at `p`) fits there.
    static func isFree(_ p: FloorPoint, radius: Double) -> Bool {
        guard p.x >= radius, p.x <= width - radius, p.y >= wall + radius, p.y <= height - radius else { return false }
        return !stations.contains { $0.footprint.grown(by: radius).contains(p) }
    }

    // MARK: Paths

    /// Grid cells for path finding, a quarter meter square.
    static let cell = 0.25
    static let columns = Int((width / cell).rounded())
    static let rows = Int((height / cell).rounded())

    private static func center(_ c: Int, _ r: Int) -> FloorPoint {
        FloorPoint((Double(c) + 0.5) * cell, (Double(r) + 0.5) * cell)
    }

    private static func cellOf(_ p: FloorPoint) -> (Int, Int) {
        (min(columns - 1, max(0, Int(p.x / cell))), min(rows - 1, max(0, Int(p.y / cell))))
    }

    /// Walkable cells, with a little room to spare around the machines.
    private static let open: [Bool] = {
        var open = [Bool](repeating: false, count: columns * rows)
        for r in 0..<rows {
            for c in 0..<columns {
                open[r * columns + c] = isFree(center(c, r), radius: Doug.radius + 0.05)
            }
        }
        return open
    }()

    /// A walkable path from `from` to somewhere Doug can work `station`, as
    /// waypoints (the first is the next one to head for). Empty if he's
    /// already there or there's no way through.
    public static func path(from: FloorPoint, to target: StationID) -> [FloorPoint] {
        let footprint = station(target).footprint
        if footprint.distance(to: from) <= reach - 0.1 { return [] }
        let goal: (Int, Int) -> Bool = { c, r in
            open[r * columns + c] && footprint.distance(to: center(c, r)) <= reach - 0.15
        }
        return route(from: from, goal: goal)
    }

    /// A walkable path to a point.
    public static func path(from: FloorPoint, to point: FloorPoint) -> [FloorPoint] {
        let (gc, gr) = cellOf(point)
        return route(from: from, goal: { c, r in c == gc && r == gr })
    }

    /// A* over the grid, then straightened where Doug can walk in a line.
    private static func route(from: FloorPoint, goal: (Int, Int) -> Bool) -> [FloorPoint] {
        var (sc, sr) = cellOf(from)
        if !open[sr * columns + sc] {
            // Standing in a corner the grid calls blocked: start from the nearest open cell.
            var best: (Int, Int)?
            var bestDistance = Double.infinity
            for r in max(0, sr - 4)...min(rows - 1, sr + 4) {
                for c in max(0, sc - 4)...min(columns - 1, sc + 4) where open[r * columns + c] {
                    let d = center(c, r).distance(to: from)
                    if d < bestDistance { bestDistance = d; best = (c, r) }
                }
            }
            guard let best else { return [] }
            (sc, sr) = best
        }
        let start = sr * columns + sc
        var cost = [Double](repeating: .infinity, count: columns * rows)
        var previous = [Int](repeating: -1, count: columns * rows)
        var closed = [Bool](repeating: false, count: columns * rows)
        cost[start] = 0
        var frontier: [(index: Int, priority: Double)] = [(index: start, priority: 0)]
        var found: Int?
        let steps = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
                     (1, 1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (-1, -1, 1.4142)]
        while !frontier.isEmpty {
            // A small grid: a linear scan for the cheapest is fast enough.
            var bestAt = 0
            for i in frontier.indices where frontier[i].priority < frontier[bestAt].priority { bestAt = i }
            let current = frontier.remove(at: bestAt).index
            if closed[current] { continue }
            closed[current] = true
            let c = current % columns
            let r = current / columns
            if goal(c, r) {
                found = current
                break
            }
            for (dc, dr, step) in steps {
                let nc = c + dc
                let nr = r + dr
                guard nc >= 0, nc < columns, nr >= 0, nr < rows else { continue }
                let next = nr * columns + nc
                guard open[next], !closed[next] else { continue }
                // No cutting corners past a machine.
                if dc != 0 && dr != 0 && (!open[r * columns + nc] || !open[nr * columns + c]) { continue }
                let newCost = cost[current] + step
                if newCost < cost[next] {
                    cost[next] = newCost
                    previous[next] = current
                    frontier.append((index: next, priority: newCost))
                }
            }
        }
        guard let found else { return [] }
        var cells: [Int] = []
        var at = found
        while at != -1 {
            cells.append(at)
            at = previous[at]
        }
        let points = cells.reversed().map { center($0 % columns, $0 / columns) }
        return straightened([from] + points).dropFirst().map { $0 }
    }

    /// Drops waypoints Doug can skip by walking straight.
    private static func straightened(_ points: [FloorPoint]) -> [FloorPoint] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        var anchor = 0
        var i = 2
        while i < points.count {
            if !clear(points[anchor], points[i]) {
                result.append(points[i - 1])
                anchor = i - 1
            }
            i += 1
        }
        result.append(points[points.count - 1])
        return result
    }

    /// Whether the straight line between two points stays clear of the machines.
    static func clear(_ a: FloorPoint, _ b: FloorPoint) -> Bool {
        let steps = max(1, Int(a.distance(to: b) / 0.1))
        for k in 0...steps {
            let t = Double(k) / Double(steps)
            if !isFree(a + (b - a) * t, radius: Doug.radius) { return false }
        }
        return true
    }
}

/// Doug, walking the floor.
public struct Doug: Equatable, Sendable {
    public enum Facing: String, Sendable {
        case down, up, left, right
    }

    /// Walking speed in meters per second, with the stick all the way over.
    public static let speed = 3.2
    /// His feet, as a circle, for bumping into things.
    public static let radius = 0.3

    public private(set) var position: FloorPoint
    public private(set) var facing = Facing.down
    public private(set) var isWalking = false
    /// Meters walked, for the walking animation.
    public private(set) var walked = 0.0

    public init(at position: FloorPoint = Floor.start) {
        self.position = position
    }

    /// Walks for `seconds` in the stick's direction (length 0...1 is how hard
    /// it's pushed), sliding along anything in the way.
    public mutating func walk(_ stick: FloorPoint, seconds: Double) {
        let push = min(1, stick.length)
        guard push > 0.12, seconds > 0 else {
            isWalking = false
            return
        }
        let direction = stick * (1 / stick.length)
        let step = direction * (Doug.speed * push * seconds)
        let before = position
        var next = FloorPoint(position.x + step.x, position.y)
        if Floor.isFree(next, radius: Doug.radius) { position = next }
        next = FloorPoint(position.x, position.y + step.y)
        if Floor.isFree(next, radius: Doug.radius) { position = next }
        let moved = position.distance(to: before)
        walked += moved
        isWalking = moved > 0.0005
        if abs(direction.x) > abs(direction.y) {
            facing = direction.x > 0 ? .right : .left
        } else {
            facing = direction.y > 0 ? .down : .up
        }
    }

    /// Turns to face a station he's working.
    public mutating func face(_ station: StationID) {
        let c = Floor.station(station).footprint.center
        let d = c - position
        if abs(d.x) > abs(d.y) {
            facing = d.x > 0 ? .right : .left
        } else {
            facing = d.y > 0 ? .down : .up
        }
        isWalking = false
    }

    public mutating func stop() { isWalking = false }
}

/// Doug and where he's headed. The stick wins; without it he walks on his own
/// to the station he was sent to (a tap, or the autopilot).
public struct Walker: Equatable, Sendable {
    public private(set) var doug: Doug
    public private(set) var destination: StationID?
    private var route: [FloorPoint] = []
    private var routeTarget: StationID?

    public init(doug: Doug = Doug()) {
        self.doug = doug
    }

    /// The station he's close enough to work.
    public var station: StationID? { Floor.station(near: doug.position) }

    public mutating func walk(to station: StationID?) {
        destination = station
        routeTarget = nil
    }

    public mutating func advance(by seconds: Double, stick: FloorPoint = .zero) {
        if stick.length > 0.12 {
            destination = nil
            doug.walk(stick, seconds: seconds)
        } else if let destination {
            follow(destination, seconds: seconds)
        } else {
            doug.stop()
        }
    }

    public mutating func face(_ station: StationID) { doug.face(station) }

    public mutating func stop() { doug.stop() }

    /// Walks towards a station along a path around the machines.
    private mutating func follow(_ station: StationID, seconds: Double) {
        if routeTarget != station {
            routeTarget = station
            route = Floor.path(from: doug.position, to: station)
        }
        while let next = route.first, next.distance(to: doug.position) < 0.06 {
            route.removeFirst()
        }
        guard let next = route.first else {
            destination = nil
            routeTarget = nil
            doug.face(station)
            return
        }
        let d = next - doug.position
        let length = d.length
        // Slow down on the last few centimeters so he doesn't overshoot.
        let push = min(1, length / (Doug.speed * seconds))
        let before = doug.position
        doug.walk(d * (push / length), seconds: seconds)
        if doug.position == before {
            // Stuck on a corner: plan again from here.
            route = Floor.path(from: doug.position, to: station)
            if route.isEmpty {
                destination = nil
                routeTarget = nil
            }
        }
    }
}
