import CrushKit
import SwiftUI

/// After the harvest: the cellar's months, the wines to make (Doug blends
/// them at the lab bench) and the lots in tank and barrel.
struct CellarSection: View {
    @Environment(GameStore.self) private var store
    let game: Game
    @State private var confirmRelease = false
    @State private var showCellar = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Aging.name(game.cellarMonth)) in the cellar").font(.headline)
                    Spacer()
                    Text(game.monthsLeft == 0 ? "Release next month" : "\(game.monthsLeft) months to the release")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Walk Doug through the cellar: top up the barrels, taste the lots, and blend and bottle each wine "
                     + "at the lab bench when it tastes right. Rosé and Sybarite are best young; the reds want time in barrel.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !game.needsTopping.isEmpty {
                    Label("The \(game.needsTopping.map { $0.name.lowercased() }.joined(separator: " and ")) need topping up.",
                          systemImage: "drop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.red)
                }
                Button {
                    showCellar = true
                } label: {
                    Label("Into the cellar with Doug", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .card()

            SectionTitle("The wines", detail: "Blended at the lab bench")
            ForEach(game.winesToShow) { wine in
                WineRow(game: game, wine: wine, link: false)
            }
            if !game.bottled.isEmpty {
                SectionTitle("Bottled", detail: "\(game.bottled.reduce(0) { $0 + $1.cases }) cases")
                ForEach(game.bottled) { wine in
                    BottledRow(wine: wine)
                }
            }

            SectionTitle("In the cellar", detail: "\(leftover) cases")
            if game.lots.isEmpty {
                Text("Nothing left in tank or barrel.")
                    .foregroundStyle(.secondary)
                    .card()
            }
            ForEach(game.lots) { lot in
                LotRow(lot: lot, vintage: game.vintage)
            }

            BillCard(bill: game.bill)

            Button {
                if leftover > 0 { confirmRelease = true } else { store.play { $0.release() } }
            } label: {
                Label("Release the \(String(game.vintage)) vintage", systemImage: "shippingbox.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .fullScreenCover(isPresented: $showCellar) { BarrelRoomView() }
        .confirmationDialog("Release the vintage?", isPresented: $confirmRelease, titleVisibility: .visible) {
            if young > 0 {
                Button("Release, and keep \(young) cases in barrel") { store.play { $0.release() } }
            }
            Button("Release, and bottle the rest as single varietals") {
                store.play { game in
                    game.bottleLeftovers()
                    game.release()
                }
            }
        } message: {
            Text(releaseMessage)
        }
    }

    private var leftover: Int { game.lots.reduce(0) { $0 + $1.cases } }

    /// This year's unbottled wine, which can stay in barrel another year.
    private var young: Int { game.lots.filter { $0.vintage >= game.vintage }.reduce(0) { $0 + $1.cases } }

    private var releaseMessage: String {
        let old = leftover - young
        var text = ""
        if young > 0 {
            text += "\(young) cases of \(String(game.vintage)) haven't been bottled. They can stay in barrel for another "
                + "year (\(Format.money(Game.cellarCostPerCase)) a case), or the crew can bottle them now: each red grape "
                + "as its own single varietal, the white as Sybarite and the rosé as rosé."
        }
        if old > 0 {
            text += (text.isEmpty ? "" : " ") + "\(old) cases of last year's wine have had their extra year: the crew "
                + "bottles them as single varietals at the release."
        }
        return text
    }
}

/// One of the four wines: ready to blend (again, if some is already
/// bottled), or not possible with what's in the cellar.
struct WineRow: View {
    let game: Game
    let wine: WineID
    /// Opens the blending lab. Off outside the lab bench.
    var link = true

    var body: some View {
        if let blocker = game.blocker(for: wine), let last = bottled.last {
            HStack(spacing: 14) {
                BottleView(wine: wine, vintage: last.vintage, color: last.color).frame(height: 76)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wine.spec.name).font(.headline)
                    Text(bottledText).font(.subheadline).foregroundStyle(.secondary)
                    Text(blocker).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: last.score)
            }
            .card()
        } else if let blocker = game.blocker(for: wine) {
            HStack(spacing: 14) {
                BottleView(wine: wine, vintage: game.vintage, color: RGB(0.85, 0.85, 0.85))
                    .frame(height: 76)
                    .saturation(0)
                    .opacity(0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wine.spec.name).font(.headline)
                    Text(blocker).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
            .card()
        } else if link {
            NavigationLink(value: wine) { ready(chevron: true) }
                .buttonStyle(.plain)
        } else {
            ready(chevron: false)
        }
    }

    private func ready(chevron: Bool) -> some View {
        HStack(spacing: 14) {
            BottleView(wine: wine, vintage: game.vintage, color: typicalColor)
                .frame(height: 76)
            VStack(alignment: .leading, spacing: 2) {
                Text(wine.spec.name).font(.headline).foregroundStyle(Theme.ink)
                Text(chevron ? (bottled.isEmpty ? "Ready to blend" : "Blend another bottling")
                             : "Ready: blend it at the lab bench")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.wine)
                Text(bottled.isEmpty ? wine.spec.kind : bottledText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var bottled: [BottledWine] { game.bottled.filter { $0.wine == wine } }

    private var bottledText: String {
        let cases = bottled.reduce(0) { $0 + $1.cases }
        return bottled.count == 1 ? "Bottled: \(cases) cases, \(bottled[0].score) pts"
            : "\(bottled.count) bottlings, \(cases) cases"
    }

    private var typicalColor: RGB {
        switch wine.spec.style {
        case .white: RGB(0.93, 0.88, 0.58)
        case .rose: RGB(0.96, 0.62, 0.58)
        case .red: RGB(0.4, 0.06, 0.15)
        }
    }
}

struct LotRow: View {
    let lot: Lot
    /// This year's vintage: older lots say which harvest they're from.
    var vintage: Int?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(lot.color))
                .overlay(Circle().stroke(Color.black.opacity(0.12)))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(lot.name).font(.subheadline.weight(.semibold))
                Text((older ? "\(String(lot.vintage)) · " : "")
                     + "\(lot.vessel.name) · \(Format.one(lot.alcohol))% · quality \(Int(lot.quality.rounded()))"
                     + (lot.needsTopping ? " · needs topping" : ""))
                    .font(.caption)
                    .foregroundStyle(older ? Theme.wine : Color.secondary)
            }
            Spacer()
            Text("\(lot.cases) cases").font(.subheadline.monospacedDigit())
        }
        .card()
    }

    private var older: Bool { vintage.map { lot.vintage < $0 } ?? false }
}

/// A wine bottled this vintage, waiting for the release.
struct BottledRow: View {
    let wine: BottledWine

    var body: some View {
        HStack(spacing: 14) {
            BottleView(wine: wine.wine, vintage: wine.vintage, color: wine.color).frame(height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(wine.vintage)) \(wine.spec.name)").font(.subheadline.weight(.semibold))
                Text("\(wine.cases) cases · \(wine.verdict)" + (wine.month.map { " · bottled in \(Aging.name($0))" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ScoreBadge(score: wine.score, size: 38)
        }
        .card()
    }
}

/// This vintage's costs so far.
struct BillCard: View {
    let bill: Bill

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Costs so far").font(.headline)
            line("Grapes", bill.grapes)
            line("Picking crews", bill.picking)
            if bill.oak > 0 { line("New oak", bill.oak) }
            if bill.cellar > 0 { line("Last year's wine in barrel", bill.cellar) }
            if bill.bottling > 0 { line("Bottling", bill.bottling) }
            Divider()
            line("Total", bill.total, bold: true)
            Text("Paid when the wine is released.").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func line(_ title: String, _ amount: Double, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Format.money(amount)).monospacedDigit()
        }
        .font(bold ? .headline : .subheadline)
    }
}
