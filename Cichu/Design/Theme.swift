import SwiftUI

enum Theme {
    static let accent = Color("AccentColor")
    static let background = Color("Canvas")
    static let surface = Color("Surface")
    static let ink = Color("Ink")
    static let hero = Color(red: 0.075, green: 0.23, blue: 0.20)
    static let mint = Color(red: 0.69, green: 0.91, blue: 0.78)
    static func color(_ kind: PlaceKind) -> Color {
        switch kind {
        case .home: Color("AccentColor")
        case .work: .blue
        case .exercise: .orange
        case .cafe: .brown
        case .study: .purple
        case .other: .teal
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28))
    }
}

struct PlaceBadge: View {
    let kind: PlaceKind
    var body: some View {
        Image(systemName: kind.symbol).font(.title3.weight(.semibold))
            .foregroundStyle(Theme.color(kind)).frame(width: 48, height: 48)
            .background(Theme.color(kind).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            Text(title).font(.largeTitle.bold()).tracking(-1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
}

struct Metric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit().contentTransition(.numericText())
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct EmptyCard: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol).font(.largeTitle).foregroundStyle(Theme.accent).accessibilityHidden(true)
                Text(title).font(.title3.bold())
                Text(message).foregroundStyle(.secondary).font(.subheadline)
            }.padding(.vertical, 12)
        }
    }
}

extension View {
    func pageCanvas() -> some View { background(Theme.background).foregroundStyle(Theme.ink) }
}
