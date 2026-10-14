import Foundation

/// Doug's crush: the stretch on the winery floor between the fruit arriving
/// and the wine going into tank or barrel, played in real time. The player
/// walks Doug from station to station and does each job at the right moment:
/// destem or press, bleed for saignée, add the yeast, punch down the cap, run
/// the chiller, press the reds and barrel down. Every one of those moments
/// shifts with how ripe the fruit was when it was picked, and how hot.
///
/// The view advances the clock and passes in the joystick, so a session plays
/// the same way for the same inputs, and the rules are tested without a phone.
public struct Winemaking: Sendable {
    public enum Stage: String, Codable, Sendable {
        /// The fruit is in the bins on the crush pad.
        case waiting
        /// Rosé: crushed into the press, the juice picking up color.
        case skinContact
        /// White: whole clusters in the press, the cycle running.
        case pressing
        /// White: pressed juice waiting for a tank or barrels.
        case juice
        /// White and rosé: the juice settling before the yeast goes in.
        case settling
        /// Red: in the fermenter before it starts fermenting (a cold soak).
        case soaking
        case fermenting
        /// Red: fermented dry and still on its skins.
        case dry
        /// Red: pressed, waiting to go into tank or barrels.
        case pressed
        case done
    }

    /// Something Doug does at a station.
    public enum Action: Equatable, Sendable {
        case destem
        /// Destem, but keep a third of the bunches whole, stems and all.
        case wholeCluster
        case crush
        case loadPress
        case cutPress
        case press
        /// Into steel, neutral barrels and new oak, shared out by `split`.
        case barrelDown
        case openBleed
        case closeBleed
        case addYeast
        case punchDown
        case chill(Bool)

        public var name: String {
            switch self {
            case .destem: "Destem"
            case .wholeCluster: "Keep ⅓ whole clusters"
            case .crush: "Crush into the press"
            case .loadPress: "Load the press"
            case .cutPress: "Stop the press"
            case .press: "Press"
            case .barrelDown: "Barrel down"
            case .openBleed: "Open the bleed valve"
            case .closeBleed: "Close the bleed valve"
            case .addYeast: "Add the yeast"
            case .punchDown: "Punch down"
            case .chill(let on): on ? "Chiller on" : "Chiller off"
            }
        }

        public var station: StationID {
            switch self {
            case .destem, .wholeCluster, .crush: .destemmer
            case .loadPress, .cutPress, .press: .press
            case .barrelDown: .barrels
            case .openBleed, .closeBleed, .punchDown: .fermenter
            case .addYeast: .lab
            case .chill: .chiller
            }
        }

        /// How Doug looks doing it.
        public var pose: Pose {
            switch self {
            case .punchDown: .punch
            case .openBleed, .closeBleed, .chill, .cutPress, .press, .loadPress: .valve
            case .addYeast: .taste
            case .destem, .wholeCluster, .crush, .barrelDown: .valve
            }
        }

        /// The player chooses how (the split at barrel-down), so Doug doesn't
        /// just do it when he gets there.
        public var needsChoice: Bool { self == .barrelDown }

        /// Seconds Doug is busy with it, and can't walk.
        var duration: Double {
            switch self {
            case .destem, .wholeCluster, .crush, .loadPress, .barrelDown: 1.4
            case .press: 1.2
            case .punchDown: 1.0
            case .addYeast: 0.9
            case .cutPress, .openBleed, .closeBleed, .chill: 0.5
            }
        }
    }

    public enum Pose: String, Sendable {
        case punch, valve, taste
    }

    /// Something worth a popup on the floor.
    public struct Event: Identifiable, Equatable, Sendable {
        public enum Tone: Sendable { case good, bad, info }

        public let id: Int
        public let text: String
        public let tone: Tone
        public let station: StationID
        /// Seconds into the session.
        public let time: Double
    }

    /// A job that wants doing, for the station bubbles and the to-do line.
    public struct Job: Equatable, Sendable {
        public let station: StationID
        public let text: String
        /// Needs doing now, not just soon.
        public let urgent: Bool
    }

    /// Rosé color, 0 (white wine) to 1 (red wine). Pale salmon, the color of
    /// Provence and of Riviera Rosé, is this band.
    public static let pink = 0.30...0.42

    /// White: juice from a whole-cluster press stopped `cut` of the way
    /// through its cycle, against the usual: about 60% a third of the way in,
    /// 95% at the bitter press juice, 105% pressed to the end.
    public static func pressYield(_ cut: Double) -> Double {
        1.05 * (1 - pow(1 - min(1, max(0, cut)), 2.5))
    }

    public let harvest: Harvest
    /// Vessels Doug can fill: new oak only once the winery has the barrels.
    public let vessels: [Vessel]
    public private(set) var stage: Stage
    /// Hours on the winery clock since the fruit came in.
    public private(set) var hours = 0.0
    /// Seconds of play.
    public private(set) var seconds = 0.0
    public private(set) var walker = Walker()
    public var doug: Doug { walker.doug }
    /// The station Doug is walking to on his own (tapped, or the autopilot).
    public var destination: StationID? { walker.destination }
    /// Seconds left on what Doug is doing, and what it is.
    public private(set) var busy = 0.0
    public private(set) var busyWith: Action?
    /// The clock runs three times as fast.
    public var fastForward = false

    /// °Brix now.
    public private(set) var sugar: Double
    /// °C.
    public private(set) var temperature: Double
    public private(set) var chilling = false
    /// Red: how dry the cap of skins is, 0 (just punched down) to 1.
    public private(set) var cap = 0.0
    /// Red: color and tannin drawn from the skins, 0...1.
    public private(set) var extraction = 0.0
    public private(set) var punchDowns = 0
    /// Volatile acidity: vinegar. Above 0.25 the critic notices.
    public private(set) var volatile = 0.0
    /// White and rosé: browning from waiting around.
    public private(set) var oxidation = 0.0
    /// White and rosé: aroma lost to a warm fermentation.
    public private(set) var aromaLoss = 0.0
    /// Red: hours fermenting above 32 °C.
    public private(set) var hotHours = 0.0
    /// Rosé: color drawn from the skins in the press. Red: the color the juice
    /// in the fermenter has now (what a bleed would take).
    public private(set) var color = 0.0
    /// White: how far through the press cycle, 0...1.
    public private(set) var pressProgress = 0.0
    public private(set) var pressCutAt: Double?
    /// Red: share of the fruit fermented as whole clusters, stems and all.
    public private(set) var wholeCluster = 0.0
    /// Red: share of the juice bled off for saignée rosé, and its color.
    public private(set) var bleed = 0.0
    public private(set) var bleeding = false
    private var bleedColorSum = 0.0
    private var bledWhileFermenting = 0.0
    /// White and rosé: how settled the juice is, 0...1.
    public private(set) var clarity = 0.0
    public private(set) var clarityAtYeast: Double?
    public private(set) var yeastAt: Double?
    public private(set) var wildStart = false
    public private(set) var processedAt: Double?
    public private(set) var crushedAt: Double?
    public private(set) var dryAt: Double?
    public private(set) var pressedAt: Double?
    public private(set) var sugarAtPress: Double?
    /// Where the wine went: the vessel with the biggest share.
    public private(set) var vessel: Vessel?
    /// How barrel-down shares the wine out. The player sets it before
    /// barreling down; new oak only if the winery has the barrels.
    public var split: VesselSplit
    /// When the juice (or the pressed red) started waiting for its next step.
    public private(set) var juiceSince = 0.0
    private var fermentStart: Double?
    /// Hours the native yeast have had to get going: slower in cold juice.
    private var wildClock = 0.0
    /// Fermentation progress, 0...1.
    private var progress = 0.0
    public private(set) var events: [Event] = []
    private var nextEventID = 0
    private var warned: Set<String> = []

    public init(harvest: Harvest, vessels: [Vessel] = [.stainless, .neutralOak]) {
        self.harvest = harvest
        self.vessels = vessels
        split = .only(harvest.style == .red ? .neutralOak : .stainless)
        stage = .waiting
        sugar = harvest.brix
        temperature = harvest.fruitTemperature
        // Vinegar from sour rot and mold comes in with the fruit.
        volatile = 0.3 * harvest.mustVolatile
    }

    // MARK: What the fruit asks for

    /// How ripe the fruit is for its style: 0 in the middle of the picking
    /// window, -1 and +1 at its edges.
    public var ripeness: Double {
        let window = harvest.varietal.window(for: harvest.style)
        return (harvest.brix - window.middle) / ((window.upperBound - window.lowerBound) / 2)
    }

    /// Hours the fruit can sit before it suffers. Hot fruit, less.
    public var freshFor: Double { harvest.fruitTemperature >= 28 ? 3 : 6 }

    /// White: where in the press cycle the bitter press juice starts. Riper
    /// fruit gives its juice, and its phenolics, sooner.
    public var pressKnee: Double { min(0.8, max(0.4, 0.6 - 0.08 * ripeness)) }

    /// Rosé and saignée: how fast the juice picks up color, per hour. Dark
    /// grapes and ripe fruit color it fast (Syrah in an hour or two, Grenache
    /// in three or four); every 10 °C warmer doubles the pace.
    public var colorRate: Double {
        let base: Double
        switch harvest.varietal {
        case .syrah: base = 0.25
        case .mourvedre: base = 0.15
        case .counoise: base = 0.08
        case .grenache, .sauvignonBlanc: base = 0.09
        case .cinsault: base = 0.065
        }
        let warmth = pow(2, (harvest.fruitTemperature - 20) / 10)
        return base * max(0.6, 1 + 0.25 * ripeness) * warmth * (harvest.style == .red ? 0.35 : 1)
    }

    /// Hours after crushing when the juice turns pale salmon, and when it's
    /// past it.
    public var pinkHours: ClosedRange<Double> {
        let k = colorRate
        return (-log(1 - Self.pink.lowerBound) / k)...(-log(1 - Self.pink.upperBound) / k)
    }

    /// Red: hours after destemming to add the yeast. A cold soak first brings
    /// out color and fruit; ripe fruit (higher pH) spoils sooner.
    public var yeastWindow: ClosedRange<Double> { 10...(30 - 6 * max(0, ripeness)) }

    /// Red: hours to leave it on the skins once it's dry. Syrah and Mourvèdre
    /// love a few days more when they're ripe; Grenache, Counoise and Cinsault
    /// lose color and turn bitter, so press those soon. Green tannins get
    /// harsher, so unripe fruit goes to the press straight away.
    public var macerationHours: Double {
        switch harvest.varietal {
        case .syrah, .mourvedre: min(60, max(8, 30 + 16 * ripeness))
        case .grenache, .counoise, .cinsault, .sauvignonBlanc: min(24, max(2, 10 + 8 * ripeness))
        }
    }

    /// How long the fermentation should take at a good temperature, in hours.
    public var expectedFermentation: Double {
        let a = fermentationSpeed
        return 4.733 / (a * (harvest.style == .red ? 1.1 : 0.3))
    }

    // MARK: Playing

    /// Real seconds to winery hours: fast while it ferments, slow at the press.
    public var hoursPerSecond: Double {
        let rate: Double
        switch stage {
        case .waiting, .juice, .pressed: rate = 1
        // Paced by the grape, so pale salmon lasts a few seconds for each one.
        case .skinContact: rate = min(1, max(0.15, 0.047 / colorRate))
        case .pressing: rate = 0.25
        case .settling: rate = 2
        case .soaking: rate = 1.5
        case .fermenting: rate = harvest.style == .red ? 3 : 8
        case .dry: rate = 4
        case .done: rate = 0
        }
        return rate * (fastForward ? 3 : 1)
    }

    public var isFinished: Bool { stage == .done }

    /// The station Doug is next to, if he's close enough to work it.
    public var station: StationID? { Floor.station(near: doug.position) }

    /// What Doug can do where he's standing.
    public var availableAction: Action? {
        guard busy <= 0, let station else { return nil }
        return action(at: station)
    }

    /// What can be done at a station right now, if anything.
    public func action(at station: StationID) -> Action? {
        actions.first { $0.station == station }
    }

    /// Everything that can be done at a station right now: the destemmer
    /// offers whole clusters as well as destemming.
    public func actions(at station: StationID) -> [Action] {
        actions.filter { $0.station == station }
    }

    /// Everything that can be done right now.
    public var actions: [Action] {
        var actions: [Action] = []
        switch stage {
        case .waiting:
            switch harvest.style {
            case .red: actions += [.destem, .wholeCluster]
            case .rose: actions.append(.crush)
            case .white: actions.append(.loadPress)
            }
        case .skinContact:
            actions.append(.press)
        case .pressing:
            actions.append(.cutPress)
        case .juice:
            actions.append(.barrelDown)
        case .settling:
            if yeastAt == nil { actions.append(.addYeast) }
            actions.append(.chill(!chilling))
        case .soaking:
            if yeastAt == nil { actions.append(.addYeast) }
            actions.append(bleeding ? .closeBleed : .openBleed)
            actions.append(.chill(!chilling))
        case .fermenting:
            if harvest.style == .red {
                actions.append(.punchDown)
                if bleeding { actions.append(.closeBleed) }
                if progress > 0.5 { actions.append(.press) }
            }
            actions.append(.chill(!chilling))
        case .dry:
            actions.append(.press)
            actions.append(.chill(!chilling))
        case .pressed:
            actions.append(.barrelDown)
        case .done:
            break
        }
        // The bleed valve and the punch-down share the fermenter: bleeding first.
        if let i = actions.firstIndex(of: .punchDown), bleeding {
            actions.remove(at: i)
        }
        return actions
    }

    /// Moves time on by `seconds` of play. The stick walks Doug (it wins over a
    /// tap); otherwise he heads for wherever he was sent.
    public mutating func advance(by seconds: Double, stick: FloorPoint = .zero) {
        guard stage != .done, seconds > 0 else { return }
        let dt = min(seconds, 0.25) // a pause shouldn't skip the fermentation
        self.seconds += dt
        if busy > 0 {
            busy = max(0, busy - dt)
            if busy == 0 { busyWith = nil }
            walker.stop()
        } else {
            walker.advance(by: dt, stick: stick)
            if let arrived = walker.arrived, actions(at: arrived).count == 1,
               action(at: arrived)?.needsChoice == false {
                act()
            }
        }
        var left = dt * hoursPerSecond
        while left > 1e-9 && stage != .done {
            let h = min(left, 0.25)
            step(h)
            left -= h
        }
    }

    /// Sends Doug to a station on his own.
    public mutating func walk(to station: StationID?) {
        walker.walk(to: station)
    }

    /// A tap on a machine: Doug walks over and does the job there, unless the
    /// job needs a choice (whole clusters at the destemmer, the split at
    /// barrel-down), which waits for the player. Any tank or barrel will do
    /// for barrel-down: the hoses reach.
    public mutating func operate(_ station: StationID) {
        let tanks: [StationID] = [.steelTank, .barrels, .newBarrels]
        let target: StationID = tanks.contains(station) && actions.contains(.barrelDown) ? .barrels : station
        walker.walk(to: target, operate: true)
    }

    /// Does whatever can be done where Doug stands, or one particular thing
    /// that can be done there.
    @discardableResult
    public mutating func act(_ choice: Action? = nil) -> Action? {
        guard busy <= 0, let station,
              let action = choice ?? self.action(at: station), action.station == station, perform(action)
        else { return nil }
        walker.face(action.station)
        busy = action.duration
        busyWith = action
        return action
    }

    /// Does something without walking there: the cellar crew, and tests.
    @discardableResult
    public mutating func perform(_ action: Action) -> Bool {
        guard actions.contains(action) else { return false }
        switch action {
        case .destem, .wholeCluster:
            processedAt = hours
            crushedAt = hours
            wildClock = 0
            stage = .soaking
            if action == .wholeCluster {
                wholeCluster = 1.0 / 3
                event("A third whole clusters", .info, .fermenter)
            } else {
                event("Into the fermenter", .info, .fermenter)
            }
        case .crush:
            processedAt = hours
            crushedAt = hours
            stage = .skinContact
            event("On the skins", .info, .press)
        case .loadPress:
            processedAt = hours
            crushedAt = hours
            stage = .pressing
            event("Pressing whole clusters", .info, .press)
        case .cutPress:
            pressCutAt = pressProgress
            stage = .juice
            juiceSince = hours
            let bitter = pressProgress > pressKnee + 0.05
            event(bitter ? "Pressed hard" : "Clean juice", bitter ? .bad : .good, .press)
        case .press:
            pressedAt = hours
            if harvest.style == .rose {
                // Pale salmon is the goal.
                let tone: Event.Tone = Self.pink.contains(color) ? .good : .bad
                event(color < Self.pink.lowerBound ? "Very pale" : color > Self.pink.upperBound ? "Too dark" : "Perfect pink!",
                      tone, .press)
                vessel = .stainless
                stage = .settling
                juiceSince = hours
                // Pressed juice is a little warmer than the fruit was; settling starts now.
                clarity = 0
                wildClock = 0
            } else {
                sugarAtPress = sugar
                if bleeding { bleeding = false }
                let early = dryAt == nil
                event(early ? "Pressed before dry" : "Pressed", early && sugar > 4 ? .bad : .good, .press)
                stage = .pressed
                juiceSince = hours
            }
        case .barrelDown:
            split = split.available(in: vessels)
            vessel = split.main
            if stage == .juice {
                stage = .settling
                clarity = 0
                wildClock = 0
            } else {
                stage = .done
            }
            event(split.used.count > 1 ? "Barreled down" : split.main.name, .good, action.station)
        case .openBleed:
            bleeding = true
            event("Bleeding off rosé", .info, .fermenter)
        case .closeBleed:
            bleeding = false
            event("Bled \(Int((bleed * 100).rounded()))%", .info, .fermenter)
        case .addYeast:
            yeastAt = hours
            if harvest.style != .red { clarityAtYeast = clarity }
            fermentStart = hours + (harvest.style == .red ? 6 : 4)
            event("Yeast in", .good, .lab)
        case .punchDown:
            punchDowns += 1
            extraction = min(1, extraction + 0.08 * (1 - extraction) * extractionFactor)
            cap = 0
            event("Punched down", .good, .fermenter)
        case .chill(let on):
            chilling = on
            event(on ? "Chiller on" : "Chiller off", .info, .chiller)
        }
        return true
    }

    /// Jobs that want doing, most urgent first.
    public var jobs: [Job] {
        var jobs: [Job] = []
        func add(_ station: StationID, _ text: String, urgent: Bool = false) {
            jobs.append(Job(station: station, text: text, urgent: urgent))
        }
        switch stage {
        case .waiting:
            let late = hours > freshFor
            switch harvest.style {
            case .red:
                let stems = harvest.greenStems < 0.2 ? "Brown stems: whole clusters would add spice"
                                                     : "Green stems: no whole clusters"
                add(.destemmer, "Destem into the fermenter. \(stems)", urgent: late)
            case .rose: add(.destemmer, "Crush the grapes into the press for a few hours on the skins", urgent: late)
            case .white: add(.press, "Load the press with whole clusters", urgent: late)
            }
        case .skinContact:
            if color >= Self.pink.lowerBound {
                add(.press, color > Self.pink.upperBound ? "Press now! It's getting dark" : "Pale salmon: press it now", urgent: true)
            } else {
                add(.press, "Press when the juice turns pale salmon")
            }
        case .pressing:
            if pressProgress >= pressKnee - 0.05 {
                add(.press, "Stop the press before the bitter press juice comes", urgent: true)
            } else {
                add(.press, "Free-run juice is flowing. Stop the press before it turns bitter")
            }
        case .juice:
            add(.barrels, "Barrel down: steel tanks, neutral or new oak", urgent: hours - juiceSince > 3)
        case .settling:
            if !chilling && temperature > 15 { add(.chiller, "Chill the juice while it settles", urgent: true) }
            if yeastAt == nil {
                if clarity >= 0.7 {
                    add(.lab, "Settled. Add the yeast", urgent: hours - juiceSince > 20)
                } else {
                    add(.lab, "Let it settle, then add the yeast")
                }
            }
        case .soaking:
            if harvest.style == .red && !bleeding && bleed < 0.05 && color >= Self.pink.lowerBound * 0.8
                && color <= Self.pink.upperBound {
                add(.fermenter, "Pink juice: bleed some off for saignée rosé?")
            }
            if bleeding { add(.fermenter, "Close the bleed valve at about 20%", urgent: bleed >= 0.18) }
            if let crushedAt, yeastAt == nil {
                let soaked = hours - crushedAt
                if soaked >= yeastWindow.lowerBound {
                    add(.lab, "Cold soak done. Add the yeast", urgent: soaked > yeastWindow.upperBound - 4)
                } else {
                    add(.lab, "Cold soaking. Add the yeast in a few hours")
                }
            }
        case .fermenting:
            if harvest.style == .red {
                if temperature > 30.5 && !chilling { add(.chiller, "Too hot! Turn the chiller on", urgent: true) }
                if temperature < 25 && chilling { add(.chiller, "Cool enough. Chiller off", urgent: temperature < 23) }
                if cap >= 0.5 { add(.fermenter, "The cap is drying out: punch down", urgent: cap >= 0.75) }
                if bleeding { add(.fermenter, "Close the bleed valve", urgent: true) }
            } else {
                if !chilling && temperature > 16 { add(.chiller, "Warm ferment: turn the chiller on", urgent: true) }
            }
        case .dry:
            let since = hours - (dryAt ?? hours)
            let target = macerationHours
            if since >= target - 6 {
                add(.press, "Dry and ready: press it now", urgent: since > target + 6)
            } else {
                add(.press, "Dry. Leave it on the skins a little longer")
            }
        case .pressed:
            add(.barrels, "Barrel down: steel tanks, neutral or new oak", urgent: hours - juiceSince > 6)
        case .done:
            break
        }
        return jobs.sorted { $0.urgent && !$1.urgent }
    }

    // MARK: The clock

    private var fermentationSpeed: Double {
        (harvest.style == .red ? 0.045 : 0.087) * 25 / (harvest.brix + 1)
    }

    /// Yeast speed by temperature: nothing at 8 °C, steady at 27 °C, and
    /// stressed above 33 °C.
    static func yeast(_ t: Double) -> Double {
        if t > 33 { return max(0.03, 25.0 / 19 * max(0.15, 1 - (t - 33) * 0.25)) }
        return max(0.03, (t - 8) / 19)
    }

    /// Cool fermentations draw less from the skins.
    private var extractionFactor: Double { temperature < 22 ? 0.5 : temperature > 32 ? 1.1 : 1 }

    private mutating func step(_ h: Double) {
        hours += h
        if bleeding { bleedStep(h) }
        switch stage {
        case .waiting:
            if harvest.style != .red && hours > freshFor {
                oxidation += 0.03 * h * (harvest.fruitTemperature >= 28 ? 1.5 : 1)
            }
            if hours > freshFor { warn("waiting", "The fruit is warming in the bins!", harvest.style == .white ? .press : .destemmer) }
        case .skinContact:
            color += (1 - color) * (1 - exp(-colorRate * h))
            if color > Self.pink.upperBound { warn("dark", "Getting dark!", .press) }
        case .pressing:
            pressProgress = min(1, pressProgress + h / 3)
            if pressProgress >= 1 {
                pressCutAt = 1
                stage = .juice
                juiceSince = hours
                event("Pressed to the end", .bad, .press)
            }
        case .juice:
            if hours - juiceSince > 3 { oxidation += 0.02 * h }
        case .settling:
            settle(h)
        case .soaking:
            color += (1 - color) * (1 - exp(-colorRate * h))
            drift(h)
            wildClock += h * wildPace
            if yeastAt == nil, wildClock > 48 {
                wildStart = true
                yeastAt = hours
                fermentStart = hours
                volatile += 0.06
                event("Native yeast took off!", .bad, .fermenter)
            }
            if let fermentStart, hours >= fermentStart { stage = .fermenting }
        case .fermenting:
            if harvest.style == .red {
                color += (1 - color) * (1 - exp(-colorRate * h))
            }
            ferment(h)
        case .dry:
            drift(h)
            if let dryAt, hours - dryAt > macerationHours + 30 {
                volatile += 0.003 * h
            }
            extraction = min(1, extraction + 0.001 * h)
        case .pressed:
            if hours - juiceSince > 12 { oxidation += 0.01 * h }
        case .done:
            break
        }
    }

    private mutating func settle(_ h: Double) {
        // Cold settling takes most of a day.
        let tau = chilling ? 10.0 : 16.0
        clarity += (1 - clarity) * (1 - exp(-h / tau))
        drift(h)
        wildClock += h * wildPace
        if yeastAt == nil && wildClock > 30 {
            wildStart = true
            yeastAt = hours
            clarityAtYeast = clarity
            fermentStart = hours
            volatile += 0.04
            event("Native yeast took off!", .bad, .lab)
        }
        if let fermentStart, hours >= fermentStart { stage = .fermenting }
    }

    /// Native yeast wake up slower in cold juice: half as fast at 10 °C.
    private var wildPace: Double { 0.5 + 0.5 * min(1, max(0, (temperature - 10) / 6)) }

    /// Temperature drifting to the cellar's 18 °C, or chilled.
    private mutating func drift(_ h: Double) {
        temperature -= 0.025 * (temperature - 18) * h
        chill(h)
    }

    private mutating func chill(_ h: Double) {
        guard chilling else { return }
        if harvest.style == .red {
            // A jacket on the fermenter: it keeps cooling until it's turned off.
            temperature -= 0.03 * (temperature - 4) * h
        } else {
            // White and rosé tanks have a thermostat: it holds 13 °C.
            if temperature > 13 { temperature -= min(temperature - 13, 0.25 * (temperature - 13) * h + 0.4 * h) }
        }
    }

    private mutating func ferment(_ h: Double) {
        let speed = fermentationSpeed * Self.yeast(temperature) * (temperature > 35 ? 0.2 : 1)
        let before = progress
        progress = min(1, progress + speed * (0.1 + progress) * (1.05 - progress) * h)
        let used = progress - before
        let consumed = used * (harvest.brix + 1.5)
        sugar = harvest.brix - progress * (harvest.brix + 1.5)
        temperature += (harvest.style == .red ? 2.4 : 1.6) * consumed
        drift(h)
        if harvest.style == .red {
            let activity = used / h / 0.012
            cap = min(1, cap + 0.045 * activity * h)
            if cap > 0.8 {
                volatile += 0.02 * (cap - 0.8) / 0.2 * h
                warn("cap", "The cap is drying out!", .fermenter)
            }
            extraction = min(1, extraction + 0.002 * h * extractionFactor)
            if temperature > 32 {
                hotHours += h
                warn("hot", "Too hot!", .chiller)
            }
        } else if temperature > 16 {
            aromaLoss += 0.004 * (temperature - 16) * h
            if temperature > 18 { warn("warm", "Running warm!", .chiller) }
        }
        if progress >= 0.995 {
            progress = 1
            sugar = -1.5
            dryAt = hours
            if bleeding { bleeding = false }
            if harvest.style == .red {
                stage = .dry
                cap = 0
                event("Dry!", .good, .fermenter)
            } else {
                stage = .done
                event("Dry!", .good, vessel == .stainless ? .steelTank : .barrels)
            }
        }
    }

    private mutating func bleedStep(_ h: Double) {
        let amount = min(0.05 * h, 0.35 - bleed)
        guard amount > 0 else {
            bleeding = false
            event("Bled all it will give", .info, .fermenter)
            return
        }
        bleed += amount
        bleedColorSum += color * amount
        if stage == .fermenting { bledWhileFermenting += amount * progress }
    }

    private mutating func event(_ text: String, _ tone: Event.Tone, _ station: StationID) {
        events.append(Event(id: nextEventID, text: text, tone: tone, station: station, time: seconds))
        nextEventID += 1
        if events.count > 12 { events.removeFirst(events.count - 12) }
    }

    /// An alarm, once per kind until things settle down.
    private mutating func warn(_ key: String, _ text: String, _ station: StationID) {
        guard !warned.contains(key) else { return }
        warned.insert(key)
        event(text, .bad, station)
    }

    // MARK: The result

    /// What came of it: the changes to the fruit's wine, and why.
    public var result: WinemakingResult {
        var r = WinemakingResult(split: harvest.style == .rose ? .only(.stainless) : split)
        let style = harvest.style

        // How long the fruit sat.
        if let processedAt {
            let late = max(0, processedAt - freshFor)
            if late > 0.5 {
                r.add("The fruit waited \(Int(processedAt.rounded())) hours", "It warmed up in the bins.",
                      quality: -min(5, 0.5 * late))
            } else {
                r.add("Straight off the truck", "Processed within \(Int(max(1, processedAt.rounded()))) hours.", quality: 0)
            }
        }

        switch style {
        case .white:
            let cut = pressCutAt ?? 1
            r.cases = Self.pressYield(cut)
            let bitter = max(0, cut - pressKnee) / (1 - pressKnee)
            if bitter > 0.02 {
                r.add("Pressed hard", bitter > 0.5 ? "Bitter press juice got in." : "A little press juice in the blend.",
                      quality: -12 * pow(bitter, 1.5))
                r.profile.fruit -= 1.0 * bitter
                r.profile.tannin += 1.4 * bitter
                r.profile.spice += 0.4 * bitter
                if bitter > 0.5 { r.faults.append(.bitter) }
            } else {
                let fine = 1 - cut / pressKnee
                r.add(fine > 0.4 ? "Free-run juice" : "Stopped the press at the sweet spot",
                      fine > 0.4 ? "The finest juice, but less of it." : "Plenty of juice and none of the bitter end.",
                      quality: 1.5 * max(0, fine))
            }
        case .rose:
            let d = Self.pink.distance(to: color)
            if d > 0.005 {
                r.add(color < Self.pink.lowerBound ? "Pressed too soon" : "Left on the skins too long",
                      color < Self.pink.lowerBound ? "Pale and a little thin." : "Dark for a rosé, with some grip.",
                      quality: -min(6, 25 * d))
            } else {
                r.add("Pale salmon", "Pressed at just the right pink.", quality: 1)
            }
            r.profile.body += 2.0 * (color - 0.36)
            r.profile.tannin += 3 * max(0, color - Self.pink.upperBound)
            r.profile.fruit += max(-0.6, min(0.4, 1.2 * (color - 0.36)))
            r.roseColor = color
        case .red:
            break
        }

        if style != .red {
            if let clarityAtYeast, !wildStart {
                if clarityAtYeast < 0.7 {
                    r.add("Yeast in cloudy juice", "Too many solids: coarse and bitter-edged.",
                          quality: -6 * (0.7 - clarityAtYeast))
                    r.profile.fruit -= 0.8 * (0.7 - clarityAtYeast)
                } else {
                    r.add("Clean, settled juice", "The yeast went into clear juice.", quality: 0.5)
                }
            }
            if aromaLoss > 0.05 {
                r.add("Warm fermentation", "The aromas blew off.", quality: -min(6, 2 * aromaLoss))
                r.profile.fruit -= min(2, 0.6 * aromaLoss)
            } else if yeastAt != nil {
                r.add("Cool fermentation", "Fresh and aromatic.", quality: 1)
                r.profile.fruit += 0.2
            }
        }

        if style == .red {
            if wildStart {
                r.add("Native yeast", "The native yeast started it before the yeast went in: funky and complex, but a gamble.",
                      quality: -1)
                r.profile.spice += 0.3
                r.profile.body += 0.2
            } else if let yeastAt, let crushedAt {
                let soaked = yeastAt - crushedAt
                if soaked < yeastWindow.lowerBound {
                    r.add("Short cold soak", "Yeast in after \(Int(soaked.rounded())) hours: less color and fruit.",
                          quality: -0.5)
                    r.profile.fruit -= 0.03 * (yeastWindow.lowerBound - soaked)
                    r.profile.body -= 0.02 * (yeastWindow.lowerBound - soaked)
                } else if soaked <= yeastWindow.upperBound {
                    r.add("Cold soak", "\(Int(soaked.rounded())) hours on the skins before the yeast: brighter fruit and color.",
                          quality: 0.5)
                    r.profile.fruit += 0.3
                } else {
                    let over = soaked - yeastWindow.upperBound
                    r.add("Long soak", "Yeast in after \(Int(soaked.rounded())) hours: spoilage crept in.",
                          quality: -min(3, 0.08 * over))
                    r.volatile += min(0.2, 0.004 * over)
                }
            }
            if hotHours > 0.5 {
                r.add("Ran hot", "\(Int(hotHours.rounded())) hours above 32 °C: cooked, stewed fruit.",
                      quality: -min(6, 0.15 * hotHours))
                r.profile.fruit -= min(1.5, 0.04 * hotHours)
            }
            let e = extraction - 0.6
            r.add(punchDowns == 0 ? "Never punched down" : "Punched down \(punchDowns) times",
                  e >= 0 ? "Good color and structure from the skins." : "Not much drawn from the skins.",
                  quality: max(-3, min(3, 8 * e)))
            r.profile.tannin += 1.8 * e
            r.profile.body += 1.2 * e
            r.profile.fruit += 0.8 * e

            if wholeCluster > 0 {
                // Brown, ripe stems give Syrah and Grenache spice and structure;
                // green ones make it stalky and steal color.
                let w = wholeCluster
                let g = harvest.greenStems
                let factors: (bonus: Double, spice: Double)
                switch harvest.varietal {
                case .syrah: factors = (3, 1)
                case .grenache: factors = (1.5, 0.5)
                case .counoise, .cinsault: factors = (0.5, 0.3)
                case .mourvedre, .sauvignonBlanc: factors = (0, 0)
                }
                let lostColor = 1.5 * g + (harvest.varietal == .grenache ? 0.3 : 0) * (1 - g)
                r.add("Whole clusters", g < 0.2 ? "A third whole bunches on brown stems: spice and structure."
                                                : "Green stems went in with the bunches: stalky.",
                      quality: factors.bonus * (1 - 2.5 * g))
                r.profile.tannin += 1.5 * w
                r.profile.spice += factors.spice * (1 - g) * w
                r.profile.fruit -= ((0.3 + 0.7 * g) + 0.6 * lostColor) * w
                r.profile.acidity -= 0.5 * w
                if g * w >= 0.15 { r.faults.append(.stemmy) }
            }

            if let pressedAt {
                if let dryAt {
                    let since = pressedAt - dryAt
                    let target = macerationHours
                    if abs(since - target) <= 8 {
                        r.add("Pressed at the right time", "\(Int(since.rounded())) hours after it went dry.", quality: 1.5)
                        if ripeness > 0 {
                            r.profile.body += 0.3
                            r.profile.tannin -= 0.2
                        }
                    } else if since < target {
                        r.add("Pressed a little early", "Ripe fruit likes more time on its skins.",
                              quality: ripeness > 0 ? -0.5 : 0)
                        if ripeness > 0 { r.profile.body -= 0.2 }
                    } else {
                        let over = since - target - 8
                        r.add("Left on the skins too long", "Drying, harsh tannins.", quality: -min(5, 0.1 * over))
                        r.profile.tannin += min(1.2, 0.03 * over)
                    }
                } else if let s = sugarAtPress {
                    // A few degrees left finish in barrel; much more and it sticks.
                    if s > 5 {
                        r.add("Pressed while sweet", "It stuck with \(Int(s.rounded()))° Brix of sugar left.",
                              quality: -min(8, 1.5 * (s - 5)))
                        if s > 8 { r.faults.append(.sweet) }
                    } else {
                        r.add("Finished in barrel", "Pressed a little sweet; it fermented dry in barrel.", quality: 0)
                    }
                }
            }

            if bleed > 0.01 {
                r.bleed = bleed
                r.bleedColor = bleedColorSum / bleed
                r.bleedQuality = -min(6, 25 * Self.pink.distance(to: r.bleedColor))
                    - (bledWhileFermenting / bleed) * 4
                r.add("Saignée", "Bled \(Int((bleed * 100).rounded()))% off as rosé: a darker, richer red.",
                      quality: 10 * bleed)
                r.profile.fruit += 2 * bleed
                r.profile.tannin += 4 * bleed
                r.profile.body += 3 * bleed
            }
        }

        if oxidation > 0.02 {
            r.add("Oxidized", "Too long in the air: tired fruit.", quality: -min(5, 8 * oxidation))
            r.profile.fruit -= 1.5 * oxidation
            if oxidation >= 0.25 { r.faults.append(.oxidized) }
        }
        r.volatile += volatile
        if r.volatile > 0.05 {
            r.add("Volatile acidity", r.volatile >= 0.25 ? "A whiff of vinegar: the cap dried out, or the yeast came late."
                                                          : "A trace of vinegar, below what anyone would notice.",
                  quality: -min(8, 20 * r.volatile))
            if r.volatile >= 0.25 { r.faults.append(.volatile) }
        }
        return r
    }
}

/// What Doug's crush did to the wine.
public struct WinemakingResult: Equatable, Sendable {
    public struct Note: Equatable, Sendable, Identifiable {
        public var title: String
        public var detail: String
        /// Quality points, plus or minus.
        public var quality: Double

        public var id: String { title }
    }

    public var notes: [Note] = []
    public var profile = TasteProfile()
    /// Cases made, as a share of the usual.
    public var cases = 1.0
    public var faults: [Fault] = []
    /// Where it went at barrel-down.
    public var split: VesselSplit
    /// The vessel with the most wine.
    public var vessel: Vessel { split.main }
    /// Red: share bled off for saignée, its color and how good that rosé is.
    public var bleed = 0.0
    public var bleedColor = 0.0
    public var bleedQuality = 0.0
    /// Rosé: the color it was pressed at.
    public var roseColor: Double?
    public var volatile = 0.0

    public init(split: VesselSplit) {
        self.split = split
    }

    public var quality: Double { notes.reduce(0) { $0 + $1.quality } }

    mutating func add(_ title: String, _ detail: String, quality: Double) {
        var title = title
        while notes.contains(where: { $0.title == title }) { title += " " }
        notes.append(Note(title: title, detail: detail, quality: quality))
    }
}
