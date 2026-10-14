import CrushKit
import SwiftUI

/// From the crush pad to the cellar: Doug makes the wine on the winery floor,
/// or the crew does it quickly.
struct CrushFlowView: View {
    enum Stage { case briefing, doug, crew }

    @Environment(GameStore.self) private var store
    let harvest: Harvest
    let done: () -> Void
    @State private var stage = Stage.briefing
    /// Made once, when Doug starts: finishing it clears the crush pad.
    @State private var session: Winemaking?

    var body: some View {
        switch stage {
        case .briefing:
            CrushBriefingView(harvest: harvest, vessels: store.game?.vessels ?? [.stainless, .neutralOak],
                              doug: {
                                  session = store.game?.startWinemaking()
                                  stage = session == nil ? .crew : .doug
                              },
                              crew: { stage = .crew })
        case .doug:
            if let session {
                WinemakingView(session: session, plan: plan(for: session)) { done() }
            }
        case .crew:
            CrushPadView(harvest: harvest) { done() }
        }
    }

    /// How the autopilot would play it: Doug's favorite vessels.
    private func plan(for session: Winemaking) -> CrushPlan {
        let vessel: Vessel
        switch harvest.style {
        case .white, .rose: vessel = .stainless
        case .red: vessel = harvest.varietal == .syrah && session.vessels.contains(.newOak) ? .newOak : .neutralOak
        }
        return CrushPlan(skill: 1, saignee: harvest.varietal == .grenache, vessel: vessel)
    }
}

/// The fruit, what Doug has to do with it, and when, before the clock starts.
struct CrushBriefingView: View {
    let harvest: Harvest
    let vessels: [Vessel]
    let doug: () -> Void
    let crew: () -> Void

    var body: some View {
        let w = Winemaking(harvest: harvest, vessels: vessels)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("On the crush pad")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.wine)
                    Text(harvest.blockName).font(.largeTitle.weight(.bold)).fontDesign(.serif)
                    Text("\(Format.tons(harvest.tons)) at \(Format.one(harvest.brix))° Brix, \(Format.one(harvest.acid)) g/L acid. "
                         + "Picked for \(styleName), \(Int(harvest.fruitTemperature.rounded()))°C off the truck.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    DougSprite(facing: .down)
                        .frame(width: 70, height: 100)
                    Text(intro(w))
                        .font(.subheadline)
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Doug's plan").font(.headline)
                    ForEach(Array(steps(w).enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(index + 1))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Theme.wine, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).font(.subheadline.weight(.semibold))
                                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .card()

                Label("Drag the stick to walk Doug, or tap a machine to send him there. When he's next to it, the big button does the job.",
                      systemImage: "hand.tap.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(20)
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: doug) {
                    Label("Make it with Doug", systemImage: "figure.walk").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Leave it to the cellar crew", action: crew)
                    .font(.subheadline.weight(.semibold))
            }
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }

    private var styleName: String {
        switch harvest.style {
        case .red: "red"
        case .rose: "rosé"
        case .white: "white"
        }
    }

    private func intro(_ w: Winemaking) -> String {
        let ripe = w.ripeness
        let fruit = ripe > 0.6 ? "Ripe fruit" : ripe < -0.6 ? "Early fruit" : "Fruit right in the window"
        let hot = harvest.fruitTemperature >= 28 ? " It came in hot, so get it processed fast." : ""
        switch harvest.style {
        case .red:
            return "\(fruit): about \(Int((w.expectedFermentation / 24).rounded())) days to ferment, "
                + "and it'll run hot without the chiller.\(hot)"
        case .rose:
            return "\(fruit): it'll turn pale salmon after about \(hours(w.pinkHours.lowerBound)) on the skins.\(hot)"
        case .white:
            return "\(fruit) for Sybarite: whole-cluster pressed, cold settled and fermented cool.\(hot)"
        }
    }

    /// Whether the stems are ripe enough to ferment some bunches whole.
    private var wholeClusters: String {
        let green = Format.percent(harvest.greenStems)
        if harvest.greenStems < 0.2 {
            return "The stems are brown (\(green) green): keeping a third whole clusters adds spice and structure, "
                + "most of all to Syrah."
        }
        return "\(green) of the fruit is on green stems: whole clusters would taste stalky."
    }

    private struct Step {
        let title: String
        let detail: String
    }

    private func steps(_ w: Winemaking) -> [Step] {
        switch harvest.style {
        case .red:
            return [
                Step(title: "Destem into the fermenter", detail: "Within \(Int(w.freshFor)) hours, before the fruit warms up. "
                     + wholeClusters),
                Step(title: "Saignée, if you like", detail: "Open the bleed valve while the juice is pink, around "
                     + "\(hours(w.pinkHours.lowerBound))–\(hours(w.pinkHours.upperBound)) after destemming. About 20% makes a darker, richer red."),
                Step(title: "Cold soak, then the yeast", detail: "Add yeast at the lab \(Int(w.yeastWindow.lowerBound))–"
                     + "\(Int(w.yeastWindow.upperBound)) hours after destemming."),
                Step(title: "Punch down and keep it cool", detail: "Punch down when the cap dries out. Keep it 24–31 °C with the chiller."),
                Step(title: "Press", detail: w.macerationHours <= 6 ? "As soon as it's dry: green tannins get harsher."
                     : "About \(hours(w.macerationHours)) after it goes dry: ripe tannins love the extra time."),
                Step(title: "Barrel down", detail: "Steel, neutral oak or new French oak."),
            ]
        case .rose:
            return [
                Step(title: "Crush into the press", detail: "Within \(Int(w.freshFor)) hours."),
                Step(title: "Press at pale salmon", detail: "About \(hours(w.pinkHours.lowerBound))–\(hours(w.pinkHours.upperBound)) on the skins."),
                Step(title: "Chill and settle", detail: "Turn the chiller on while the juice settles in the steel tank."),
                Step(title: "Add the yeast", detail: "Once it's settled, and before wild yeast get going (about a day)."),
            ]
        case .white:
            return [
                Step(title: "Load the press", detail: "Whole clusters, within \(Int(w.freshFor)) hours."),
                Step(title: "Stop the press", detail: "Before the bitter press juice: around \(Format.one(w.pressKnee * 2)) bar for this fruit."),
                Step(title: "Into tank or barrel", detail: "Steel for zip, neutral oak for a rounder Sybarite."),
                Step(title: "Chill, settle, add yeast", detail: "Cold settle with the chiller on, then the yeast once it's clear."),
            ]
        }
    }

    private func hours(_ h: Double) -> String {
        let rounded = max(1, Int(h.rounded()))
        return rounded == 1 ? "an hour" : "\(rounded) hours"
    }
}
