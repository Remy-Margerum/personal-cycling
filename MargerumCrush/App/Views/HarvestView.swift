import CrushKit
import SwiftUI

/// A crew heading into a block, and what it's picking for.
struct PickRequest: Identifiable {
    let id = UUID()
    let block: VineyardBlock
    let style: WineStyle
    let round: PickingRound
}

/// The harvest: forecast, vineyard blocks and the calendar.
struct HarvestSection: View {
    @Environment(GameStore.self) private var store
    let game: Game
    @State private var request: PickRequest?
    @State private var finishingCrush = false
    @State private var confirmEnd = false

    var body: some View {
        VStack(spacing: 14) {
            if let advice = game.advice {
                Label(advice, systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.gold.opacity(0.18), in: .rect(cornerRadius: 14))
            }
            ForecastCard(game: game)
            if let harvest = game.crushPad, request == nil {
                // Picked, but the app closed before the fruit was crushed.
                Button {
                    finishingCrush = true
                } label: {
                    Label("\(harvest.blockName) is waiting on the crush pad", systemImage: "exclamationmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            SectionTitle("Vineyard", detail: crewText)
            ForEach(game.blocks) { block in
                BlockCard(block: block, canPick: game.canPick(block.id)) { style in
                    pick(block, for: style)
                }
            }
            weekControls
            DiaryCard(entries: game.diary)
        }
        .fullScreenCover(item: $request) { request in
            PickFlowView(request: request)
        }
        .fullScreenCover(isPresented: $finishingCrush) {
            if let harvest = store.game?.crushPad {
                CrushFlowView(harvest: harvest) { finishingCrush = false }
            }
        }
        .confirmationDialog("End the harvest now?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Leave it for the rain", role: .destructive) { store.play { $0.finishHarvest() } }
        } message: {
            Text("Still on the vine: \(game.blocks.filter { !$0.picked }.map(\.name).joined(separator: ", ")). It will be lost.")
        }
    }

    private var crewText: String {
        if game.picksLeft == 0 { return "Crews busy until next week" }
        return "\(game.picksLeft) of \(game.crewSize) \(game.crewSize == 1 ? "crew" : "crews") free"
    }

    private func pick(_ block: VineyardBlock, for style: WineStyle) {
        guard let round = store.startPicking(block.id, for: style) else { return }
        request = PickRequest(block: block, style: style, round: round)
    }

    @ViewBuilder private var weekControls: some View {
        VStack(spacing: 8) {
            if game.blocks.allSatisfy(\.picked) {
                Button {
                    store.play { $0.finishHarvest() }
                } label: {
                    Label("The harvest is in. To the cellar!", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    store.play { $0.nextWeek() }
                } label: {
                    Label(game.isLastWeek ? "Wait for the rain (ends the harvest)"
                                          : "Wait until \(HarvestCalendar.date(week: game.week + 1))",
                          systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(game.crushPad != nil)
                Button("End the harvest now", role: .destructive) { confirmEnd = true }
                    .font(.footnote)
            }
        }
        .controlSize(.large)
        .padding(.vertical, 4)
    }
}

struct ForecastCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Forecast").font(.headline)
                Spacer()
                Text(game.owns(.weatherStation) ? "Weather station: right 9 times in 10" : "Right about 3 times in 4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(game.forecast) { day in
                HStack(spacing: 12) {
                    Image(systemName: day.weather.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.title2)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(day.week == game.week ? "This week" : "Week of \(day.date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(day.weather.name).font(.subheadline.weight(.semibold))
                        Text(day.weather.effect).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
    }
}

struct BlockCard: View {
    let block: VineyardBlock
    let canPick: Bool
    let pick: (WineStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                GrapeCluster(color: Color(block.varietal.berryColor))
                    .frame(width: 30, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.name).font(.headline)
                    Text(block.appellation).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.tons(block.tons))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if block.picked {
                Label("Picked", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.leaf)
            } else {
                HStack(spacing: 18) {
                    stat("Sugar", "\(Format.one(block.brix))° Brix")
                    stat("Acid", "\(Format.one(block.acid)) g/L")
                    stat("Mold", Format.percent(block.rot), warn: block.rot >= 0.06)
                }
                RipenessGauge(block: block)
                HStack(spacing: 8) {
                    RipenessChip(ripeness: block.ripeness(for: block.varietal.mainStyle),
                                 prefix: block.varietal.isRed ? "Red: " : "")
                    if block.varietal.isRed {
                        RipenessChip(ripeness: block.ripeness(for: .rose), prefix: "Rosé: ")
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        pick(block.varietal.mainStyle)
                    } label: {
                        Label(block.varietal.isRed ? "Pick for red" : "Pick", systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    if block.varietal.isRed {
                        Button {
                            pick(.rose)
                        } label: {
                            Text("Pick for rosé").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .disabled(!canPick)
            }
        }
        .card()
    }

    private func stat(_ title: String, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(warn ? Color.red : Theme.ink)
        }
    }
}

struct RipenessChip: View {
    let ripeness: Ripeness
    var prefix = ""

    var body: some View {
        Text(prefix + ripeness.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch ripeness {
        case .early: Color.gray
        case .almost: Color.orange
        case .ready: Theme.leaf
        case .late: Color(red: 0.8, green: 0.35, blue: 0.1)
        case .raisined: Color.red
        }
    }
}

/// Sugar on a scale from 18 to 28 °Brix, with the picking windows marked:
/// green for red or white wine, pink for rosé.
struct RipenessGauge: View {
    let block: VineyardBlock
    private static let scale = 18.0...28.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.06)).frame(height: 10)
                if block.varietal.isRed {
                    band(block.varietal.window(for: .rose), width: w, color: Color.pink.opacity(0.45))
                }
                band(block.varietal.window(for: block.varietal.mainStyle), width: w, color: Theme.leaf.opacity(0.55))
                Circle()
                    .fill(Theme.wine)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .frame(width: 16, height: 16)
                    .offset(x: x(block.brix, width: w) - 8)
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sugar \(Format.one(block.brix)) Brix")
    }

    private func band(_ window: ClosedRange<Double>, width: CGFloat, color: Color) -> some View {
        let start = x(window.lowerBound, width: width)
        let end = x(window.upperBound, width: width)
        return Capsule()
            .fill(color)
            .frame(width: end - start, height: 10)
            .offset(x: start)
    }

    private func x(_ brix: Double, width: CGFloat) -> CGFloat {
        let scale = Self.scale
        let clamped = min(max(brix, scale.lowerBound), scale.upperBound)
        return width * CGFloat((clamped - scale.lowerBound) / (scale.upperBound - scale.lowerBound))
    }
}

struct DiaryCard: View {
    let entries: [DiaryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Harvest diary").font(.headline)
            ForEach(Array(entries.suffix(8).reversed())) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.date)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .leading)
                    Text(entry.text).font(.subheadline)
                }
            }
        }
        .card()
    }
}
