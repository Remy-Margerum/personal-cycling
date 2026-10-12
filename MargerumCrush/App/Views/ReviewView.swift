import CrushKit
import SwiftUI

/// The critic's verdict on a bottled wine.
struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let wine: BottledWine
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("THE VALLEY CRITIC")
                    .font(.caption.weight(.bold))
                    .tracking(3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
                BottleView(wine: wine.wine, vintage: wine.vintage, color: wine.color)
                    .frame(height: 230)
                VStack(spacing: 2) {
                    Text("\(String(wine.vintage)) \(wine.spec.name)")
                        .font(.title2.weight(.bold))
                        .fontDesign(.serif)
                    Text(wine.spec.kind).font(.subheadline).foregroundStyle(.secondary)
                }
                ScoreBadge(score: wine.score, size: 92)
                    .scaleEffect(revealed ? 1 : 0.2)
                    .opacity(revealed ? 1 : 0)
                Text(wine.verdict.uppercased())
                    .font(.headline)
                    .tracking(2)
                    .foregroundStyle(Theme.wine)
                Text("“\(wine.note)”")
                    .font(.body)
                    .italic()
                    .fontDesign(.serif)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Text(wine.composition.map { "\($0.varietal.name) \(Format.percent($0.share))" }.joined(separator: " · "))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("\(wine.cases) cases · \(Format.one(wine.alcohol))% alcohol")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let revenue = wine.revenue {
                    Text("Sold for \(Format.money(revenue))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.leaf)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .sensoryFeedback(.success, trigger: revealed)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.45).delay(0.35)) { revealed = true }
        }
    }
}
