import SwiftUI

enum Theme {
    static let accent = Color("AccentColor")
    static let background = Color("Canvas")
    static let surface = Color("Surface")
    static let ink = Color("Ink")
    static let quiet = Color("Quiet")
    static let highlight = Color("Highlight")
    static let onAccent = Color("OnAccent")
    // Exact stops from DesignAssets/AppIcon/location-mark.svg. Decorative brand use only.
    static let brandStart = Color(red: 1, green: 140.0 / 255, blue: 66.0 / 255)
    static let brandEnd = Color(red: 244.0 / 255, green: 81.0 / 255, blue: 30.0 / 255)
    static let brand = LinearGradient(colors: [brandStart, brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func color(_ kind: PlaceKind) -> Color {
        Color("Place-" + kind.rawValue)
    }
}

enum Motion {
    static let press = Animation.easeOut(duration: 0.12)
    static let change = Animation.easeOut(duration: 0.2)
    static let expand = Animation.spring(duration: 0.28, bounce: 0.08)
}

struct AdaptiveRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        layout { content }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct PlaceBadge: View {
    let kind: PlaceKind
    var body: some View {
        Image(systemName: kind.symbol).font(.body.weight(.medium))
            .foregroundStyle(Theme.color(kind)).frame(width: 40, height: 40)
            .background(Theme.color(kind).opacity(0.08), in: Circle())
            .accessibilityHidden(true)
    }
}

struct PageHeading: View {
    let title: String
    var body: some View {
        Text(title).font(.largeTitle.weight(.semibold)).tracking(-0.5)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
}

struct Metric: View {
    let title: String
    let value: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(Theme.quiet)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : Motion.change, value: value)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
    }
}

struct EmptyCard: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Theme.accent).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).foregroundStyle(Theme.quiet).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Geometric reproduction of the repository's canonical SVG, not a replacement icon.
struct BrandMark: View {
    var body: some View {
        GeometryReader { geometry in
            Path { p in
                p.move(to: CGPoint(x: 512, y: 98.133))
                p.addCurve(to: CGPoint(x: 121.6, y: 479.147), control1: CGPoint(x: 288, y: 98.133), control2: CGPoint(x: 121.6, y: 264.533))
                p.addCurve(to: CGPoint(x: 512, y: 998.4), control1: CGPoint(x: 121.6, y: 715.52), control2: CGPoint(x: 356.267, y: 878.08))
                p.addCurve(to: CGPoint(x: 902.4, y: 479.147), control1: CGPoint(x: 667.733, y: 878.08), control2: CGPoint(x: 902.4, y: 715.52))
                p.addCurve(to: CGPoint(x: 512, y: 98.133), control1: CGPoint(x: 902.4, y: 264.533), control2: CGPoint(x: 736, y: 98.133))
                p.closeSubpath()
                p.addEllipse(in: CGRect(x: 318.72, y: 298.667, width: 386.56, height: 386.56))
            }.applying(CGAffineTransform(scaleX: geometry.size.width / 1024, y: geometry.size.height / 1024))
                .fill(Theme.brand, style: FillStyle(eoFill: true))
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

extension View {
    func pageCanvas() -> some View { background(Theme.background).foregroundStyle(Theme.ink) }
}


struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 48)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
    }
}


private struct UndoNotice: View {
    @Environment(JournalStore.self) private var store
    var body: some View {
        if let label = store.undoLabel {
            AdaptiveRow(spacing: 4) {
                Text(label).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                HStack(spacing: 16) {
                    Button("撤销") { store.undoLastEdit() }
                        .font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                    Button { store.dismissUndo() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("关闭撤销提示")
                }
            }.padding(.horizontal, 20).padding(.vertical, 8).background(Theme.surface)
        }
    }
}

extension View {
    func undoNotice() -> some View { safeAreaInset(edge: .bottom, spacing: 0) { UndoNotice() } }
}
