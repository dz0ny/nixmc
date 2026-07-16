import AppKit
import SwiftUI

/// One selectable accent palette: the two brand-gradient stops plus the solid
/// accent used for tint, icons, and borders.
struct ThemePalette: Identifiable, Equatable {
    let id: String
    let name: String
    let start: Color
    let end: Color
    let accent: Color
}

/// Shared visual language: one accent gradient, compact controls, and quiet surfaces.
///
/// The palette is user-selectable (Settings → Appearance). `AppSettings` calls
/// `apply(id:)` on the main thread, and the window remounts on the theme id
/// (see `NixmcApp`), so every static lookup below re-reads the new palette.
enum Theme {
    static let palettes: [ThemePalette] = [
        ThemePalette(id: "indigo", name: "Indigo",
                     start: Color(red: 0.36, green: 0.42, blue: 0.95),
                     end: Color(red: 0.58, green: 0.36, blue: 0.92),
                     accent: Color(red: 0.45, green: 0.40, blue: 0.94)),
        ThemePalette(id: "ocean", name: "Ocean",
                     start: Color(red: 0.10, green: 0.50, blue: 0.94),
                     end: Color(red: 0.13, green: 0.72, blue: 0.86),
                     accent: Color(red: 0.11, green: 0.58, blue: 0.90)),
        ThemePalette(id: "forest", name: "Forest",
                     start: Color(red: 0.13, green: 0.62, blue: 0.40),
                     end: Color(red: 0.10, green: 0.53, blue: 0.62),
                     accent: Color(red: 0.12, green: 0.58, blue: 0.47)),
        ThemePalette(id: "sunset", name: "Sunset",
                     start: Color(red: 0.95, green: 0.48, blue: 0.22),
                     end: Color(red: 0.90, green: 0.30, blue: 0.50),
                     accent: Color(red: 0.92, green: 0.42, blue: 0.34)),
        ThemePalette(id: "orchid", name: "Orchid",
                     start: Color(red: 0.62, green: 0.32, blue: 0.92),
                     end: Color(red: 0.86, green: 0.30, blue: 0.72),
                     accent: Color(red: 0.72, green: 0.32, blue: 0.84)),
        ThemePalette(id: "graphite", name: "Graphite",
                     start: Color(red: 0.35, green: 0.37, blue: 0.43),
                     end: Color(red: 0.52, green: 0.54, blue: 0.60),
                     accent: Color(red: 0.44, green: 0.46, blue: 0.52)),
    ]

    static let defaultPaletteID = "indigo"

    /// The active palette. Written only from the main thread (`AppSettings`).
    private(set) static var current: ThemePalette = palettes[0]

    static func apply(id: String) {
        current = palettes.first { $0.id == id } ?? palettes[0]
    }

    /// Signature gradient — used for the mark and primary actions.
    static var brand: LinearGradient {
        LinearGradient(colors: [current.start, current.end],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var brandSoft: LinearGradient {
        LinearGradient(colors: [current.start.opacity(0.16), current.end.opacity(0.16)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var accent: Color { current.accent }

    static let cardRadius: CGFloat = 8
    static let controlRadius: CGFloat = 7
}

/// A flat, hairline-bordered surface for cards and panels.
struct Card: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var hover = false
    func body(content: Content) -> some View {
        content
            .background(
                Color.primary.opacity(hover ? 0.055 : 0.035),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(hover ? Theme.accent.opacity(0.4) : Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(hover ? 0.06 : 0), radius: 4, y: 2)
    }
}

extension View {
    func card(radius: CGFloat = Theme.cardRadius, hover: Bool = false) -> some View {
        modifier(Card(radius: radius, hover: hover))
    }
}

/// The app mark, shared by headers and setup screens.
struct BrandMark: View {
    var size: CGFloat = 22

    private var icon: NSImage? {
        guard let url = AppResources.bundle.url(forResource: "nixmc-icon", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    @ViewBuilder
    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.18), radius: size * 0.12, y: 1)
        } else {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.brand)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: size * 0.56, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}

/// Filled button used for primary actions (Send, Apply, Use).
struct BrandButtonStyle: ButtonStyle {
    var compact = false
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.accent)
    /// SwiftUI doesn't dim custom button styles when `.disabled` — do it here.
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.65))
            .padding(.horizontal, compact ? 10 : 13)
            .padding(.vertical, compact ? 5 : 7)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .saturation(isEnabled ? 1 : 0)
            .opacity(pressedOrDisabled(configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func pressedOrDisabled(_ pressed: Bool) -> Double {
        if !isEnabled { return 0.5 }
        return pressed ? 0.8 : 1
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }
    static var brandCompact: BrandButtonStyle { BrandButtonStyle(compact: true) }
    static var brandDanger: BrandButtonStyle {
        BrandButtonStyle(fill: AnyShapeStyle(Color(red: 0.85, green: 0.3, blue: 0.3)))
    }
}
