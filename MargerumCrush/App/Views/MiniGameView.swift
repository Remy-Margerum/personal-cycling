import CrushKit
import SwiftUI

/// The picking game itself: three trellis wires, bunches popping up on
/// them, and the odd wasp. `PickFlowView` runs the clock.
struct MiniGameView: View {
    @Binding var round: PickingRound
    let varietal: Varietal
    let quit: () -> Void

    var body: some View {
        ZStack {
            VineyardBackdrop().ignoresSafeArea()
            VStack(spacing: 0) {
                hud
                GeometryReader { geo in
                    let size = geo.size
                    ZStack {
                        Trellis()
                        ForEach(round.clusters) { cluster in
                            clusterView(cluster, in: size)
                        }
                        ForEach(round.wasps) { wasp in
                            waspView(wasp, in: size)
                        }
                        ForEach(round.popups) { popup in
                            popupView(popup, in: size)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: goodPicks)
        .sensoryFeedback(.error, trigger: badPicks)
    }

    private var goodPicks: Int { round.tally.ripe + round.tally.golden }
    private var badPicks: Int { round.tally.unripe + round.tally.rotten + round.tally.stings }

    private var hud: some View {
        VStack(spacing: 6) {
            scoreboard
            // How much of the crop is in: three bunches in four is all of it.
            HStack(spacing: 8) {
                Text("Crop").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ProgressView(value: round.harvestedShare).tint(Theme.leaf)
                Text(Format.percent(round.harvestedShare))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var scoreboard: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: quit) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .tint(Theme.ink)
            .accessibilityLabel("Stop picking")
            Spacer()
            VStack(spacing: 0) {
                Text(String(Int(round.timeLeft.rounded(.up))))
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(round.timeLeft < 5 ? Color.red : Theme.ink)
                Text("seconds").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(round.points))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(round.multiplier > 1 ? "×\(round.multiplier) streak" : "\(round.tally.picked) picked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(round.multiplier > 1 ? Theme.gold : Color.secondary)
            }
            .frame(minWidth: 80, alignment: .trailing)
        }
    }

    private func clusterView(_ cluster: PickingRound.Cluster, in size: CGSize) -> some View {
        let spot = PickingRound.spots[cluster.spot]
        // Pop in quickly, fade as it withers.
        let grow = min(1, max(0, cluster.age(at: round.time) / 0.15))
        let fade = min(1, max(0, cluster.remaining(at: round.time) / 0.35))
        let x = size.width * CGFloat(spot.x)
        let y = size.height * CGFloat(spot.y) + 44
        return ClusterSprite(kind: cluster.kind, varietal: varietal)
            .frame(width: 66, height: 88)
            .scaleEffect(0.4 + 0.6 * grow, anchor: .top)
            .opacity(fade)
            .contentShape(Rectangle())
            .onTapGesture { round.pick(cluster.id) }
            .position(x: x, y: y)
            .accessibilityLabel(label(for: cluster.kind))
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func waspView(_ wasp: PickingRound.Wasp, in size: CGSize) -> some View {
        if let p = wasp.position(at: round.time) {
            WaspSprite()
                .frame(width: 50, height: 50)
                .scaleEffect(x: wasp.fromLeft ? 1 : -1, y: 1)
                .rotationEffect(.degrees(6 * sin(round.time * 40)))
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
                .onTapGesture { round.swat(wasp.id) }
                .position(x: size.width * CGFloat(p.x), y: size.height * CGFloat(p.y))
                .accessibilityLabel("Wasp")
        }
    }

    private func popupView(_ popup: PickingRound.Popup, in size: CGSize) -> some View {
        let age = round.time - popup.born
        return Text(popup.text)
            .font(.system(size: popup.tone == .bonus ? 22 : 18, weight: .heavy, design: .rounded))
            .foregroundStyle(color(popup.tone))
            .shadow(color: .black.opacity(0.6), radius: 2)
            .opacity(max(0, 1 - age / 0.9))
            .position(x: size.width * CGFloat(popup.x), y: size.height * CGFloat(popup.y) + 40 - CGFloat(age) * 60)
            .allowsHitTesting(false)
    }

    private func color(_ tone: PickingRound.Popup.Tone) -> Color {
        switch tone {
        case .good: .white
        case .bonus: Color(red: 1, green: 0.85, blue: 0.3)
        case .bad: Color(red: 1, green: 0.45, blue: 0.4)
        }
    }

    private func label(for kind: PickingRound.Kind) -> String {
        switch kind {
        case .ripe: "Ripe bunch"
        case .unripe: "Green bunch"
        case .rotten: "Moldy bunch"
        case .golden: "Perfect bunch"
        }
    }
}
