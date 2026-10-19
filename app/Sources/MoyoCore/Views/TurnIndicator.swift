import SwiftUI

/// The stone showing whose turn it is, ringed by a spinner while the AI thinks.
///
/// Nothing is added to the screen when the AI is working: the indication is carried
/// by the dot that was already there.
public struct TurnIndicator: View {
    public let color: PlayerColor
    public let isThinking: Bool
    public var diameter: CGFloat = 16

    @State private var angle: Double = 0

    public init(color: PlayerColor, isThinking: Bool, diameter: CGFloat = 16) {
        self.color = color
        self.isThinking = isThinking
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(Theme.stone(color))
                .frame(width: diameter, height: diameter)

            if isThinking {
                Circle()
                    .trim(from: 0, to: 0.26)
                    .stroke(Theme.primaryText.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: diameter * 1.5, height: diameter * 1.5)
                    .rotationEffect(.degrees(angle))
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                            angle = 360
                        }
                    }
                    .onDisappear { angle = 0 }
            }
        }
        .frame(width: diameter * 1.5, height: diameter * 1.5)
        .accessibilityLabel(
            isThinking ? "À \(Theme.name(color)) de jouer, l'adversaire réfléchit" : "À \(Theme.name(color)) de jouer"
        )
    }
}
