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
            ForEach(WineID.allCases) { wine in
                WineRow(game: game, wine: wine, link: false)
            }

            SectionTitle("In the cellar", detail: "\(leftover) cases")
            if game.lots.isEmpty {
                Text("Nothing left in tank or barrel.")
                    .foregroundStyle(.secondary)
                    .card()
            }
            ForEach(game.lots) { lot in
                LotRow(lot: lot)
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
            Button("Release, and sell the rest in bulk") { store.play { $0.release() } }
        } message: {
            Text("\(leftover) cases haven't been bottled. They'll be sold off as bulk wine for "
                 + "\(Format.money(Game.bulkPricePerCase)) a case.")
        }
    }

    private var leftover: Int { game.lots.reduce(0) { $0 + $1.cases } }
}

/// One of the four wines: bottled, ready to blend, or not possible yet.
struct WineRow: View {
    let game: Game
    let wine: WineID
    /// Opens the blending lab. Off outside the lab bench.
    var link = true

    var body: some View {
        if let bottled = game.bottled.first(where: { $0.wine == wine }) {
            HStack(spacing: 14) {
                BottleView(wine: wine, vintage: game.vintage, color: bottled.color).frame(height: 76)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wine.spec.name).font(.headline)
                    Text("\(bottled.cases) cases · \(bottled.verdict)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: bottled.score)
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
                Text(chevron ? "Ready to blend" : "Ready: blend it at the lab bench")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.wine)
                Text(wine.spec.kind).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .card()
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

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(lot.color))
                .overlay(Circle().stroke(Color.black.opacity(0.12)))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(lot.name).font(.subheadline.weight(.semibold))
                Text("\(lot.vessel.name) · \(Format.one(lot.alcohol))% · quality \(Int(lot.quality.rounded()))"
                     + (lot.needsTopping ? " · needs topping" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(lot.cases) cases").font(.subheadline.monospacedDigit())
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
