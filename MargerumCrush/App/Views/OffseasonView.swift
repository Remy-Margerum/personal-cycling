import CrushKit
import SwiftUI

/// Winter: how the vintage sold, and what to spend the money on.
struct OffseasonSection: View {
    @Environment(GameStore.self) private var store
    let game: Game

    var body: some View {
        VStack(spacing: 14) {
            if let report = game.report {
                ReportCard(report: report)
            }
            SectionTitle("Invest", detail: "\(Format.money(game.money)) in the bank")
            ForEach(Upgrade.allCases) { upgrade in
                UpgradeRow(upgrade: upgrade, game: game) {
                    store.play { $0.buy(upgrade) }
                }
            }
            Button {
                store.play { $0.startNextVintage() }
            } label: {
                Label("Start the \(String(game.vintage + 1)) harvest", systemImage: "leaf.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
    }
}

struct ReportCard: View {
    let report: VintageReport
    @State private var selected: BottledWine?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The \(String(report.vintage)) vintage")
                .font(.title3.weight(.bold))
                .fontDesign(.serif)
            if report.wines.isEmpty && report.bulkCases == 0 {
                Text("No wine this year.").foregroundStyle(.secondary)
            }
            ForEach(report.wines) { wine in
                Button {
                    selected = wine
                } label: {
                    HStack(spacing: 12) {
                        ScoreBadge(score: wine.score, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(wine.spec.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("\(wine.cases) cases").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.money(wine.revenue ?? 0))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.ink)
                    }
                }
                .buttonStyle(.plain)
            }
            if report.bulkCases > 0 {
                line("Bulk wine, \(report.bulkCases) cases", report.bulkSales)
            }
            Divider()
            line("Grapes", -report.bill.grapes)
            line("Picking crews", -report.bill.picking)
            if report.bill.oak > 0 { line("New oak", -report.bill.oak) }
            line("Bottling", -report.bill.bottling)
            Divider()
            HStack {
                Text("Profit").font(.headline)
                Spacer()
                Text(Format.money(report.profit))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(report.profit >= 0 ? Theme.leaf : Color.red)
            }
            HStack {
                Text("Reputation").font(.subheadline)
                Spacer()
                Stars(reputation: report.reputationAfter)
                Text(reputationChange).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if report.lostTons > 0 {
                Text("Lost to the rain: \(Format.tons(report.lostTons)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .sheet(item: $selected) { wine in ReviewView(wine: wine) }
    }

    private var reputationChange: String {
        let change = Int((report.reputationAfter - report.reputationBefore).rounded())
        return change >= 0 ? "+\(change)" : String(change)
    }

    private func line(_ title: String, _ amount: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Format.money(amount)).monospacedDigit()
        }
        .font(.subheadline)
    }
}

struct UpgradeRow: View {
    let upgrade: Upgrade
    let game: Game
    let buy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: upgrade.symbol)
                .font(.title3)
                .foregroundStyle(Theme.wine)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(upgrade.name).font(.subheadline.weight(.semibold))
                Text(upgrade.blurb).font(.caption).foregroundStyle(.secondary)
                if let needed = upgrade.requires, !game.owns(needed) {
                    Text("Needs the \(needed.name.lowercased()) first.")
                        .font(.caption2)
                        .foregroundStyle(Theme.wine)
                }
            }
            Spacer(minLength: 8)
            if game.owns(upgrade) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.leaf)
                    .accessibilityLabel("Owned")
            } else {
                Button(Format.money(upgrade.cost), action: buy)
                    .buttonStyle(.bordered)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .disabled(!game.canBuy(upgrade))
            }
        }
        .card()
    }
}
