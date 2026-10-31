//
//  Bauhaus.swift
//  Title Capitalizr
//
//  The Bauhaus design language shared with John's other apps (OrchPCB, Jeb's):
//  white ground, black ink, Jost geometric type, thick black rules, square edges,
//  and the three primaries as flat fields that carry meaning (blue = action and
//  selection, yellow = attention, red = Pro and errors). No gradients, shadows or
//  rounded corners; SF Symbols for every icon, never decorative shapes.
//

import SwiftUI
import CoreText

enum Bauhaus {
    enum Palette {
        static let ground = Color.white
        static let ink = Color.black
        /// #3C3C3C, 10.4:1 on white.
        static let inkSecondary = Color(red: 0x3C / 255, green: 0x3C / 255, blue: 0x3C / 255)
        /// #0F3FA8, 9.1:1 on white; white text on it 9.1:1.
        static let blue = Color(red: 0x0F / 255, green: 0x3F / 255, blue: 0xA8 / 255)
        /// #F2C230, always with black ink (12.6:1).
        static let yellow = Color(red: 0xF2 / 255, green: 0xC2 / 255, blue: 0x30 / 255)
        /// #D62828 fill, used with black or white bold labels.
        static let red = Color(red: 0xD6 / 255, green: 0x28 / 255, blue: 0x28 / 255)
        /// #A61B1B for red text on white (7.6:1).
        static let redInk = Color(red: 0xA6 / 255, green: 0x1B / 255, blue: 0x1B / 255)
        /// #F2F2F2 quiet field.
        static let groundSoft = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF2 / 255)
        /// #767676, disabled controls only.
        static let inkDisabled = Color(red: 0x76 / 255, green: 0x76 / 255, blue: 0x76 / 255)
    }

    enum Typo {
        static let family = "Jost"
        static func font(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
            Font.custom(family, size: size, relativeTo: style).weight(weight)
        }
        static let display = font(34, weight: .bold, relativeTo: .largeTitle)
        static let title = font(24, weight: .bold, relativeTo: .title2)
        static let section = font(12, weight: .bold, relativeTo: .caption)
        static let body = font(16, relativeTo: .body)
        static let bodyBold = font(16, weight: .semibold, relativeTo: .body)
        static let caption = font(13, relativeTo: .caption)
        static let button = font(15, weight: .semibold, relativeTo: .callout)
        static let result = font(22, weight: .medium, relativeTo: .title3)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Rule {
        static let thin: CGFloat = 1
        static let regular: CGFloat = 2
        static let thick: CGFloat = 4
        static let heavy: CGFloat = 8
    }

    static let tapTarget: CGFloat = 44

    /// Registers the bundled Jost fonts (SIL Open Font License) for this process.
    static func registerFonts() {
        for name in ["Jost[wght]", "Jost-Italic[wght]"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - Primitives

struct HRule: View {
    var thickness: CGFloat = Bauhaus.Rule.regular
    var color: Color = Bauhaus.Palette.ink
    var body: some View { color.frame(height: thickness).accessibilityHidden(true) }
}

struct VRule: View {
    var thickness: CGFloat = Bauhaus.Rule.regular
    var body: some View { Bauhaus.Palette.ink.frame(width: thickness).accessibilityHidden(true) }
}

/// Uppercase tracked label with a thick rule beneath.
struct SectionTitle<Accessory: View>: View {
    let text: String
    let accessory: Accessory

    init(_ text: String, @ViewBuilder accessory: () -> Accessory) {
        self.text = text
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            HStack(alignment: .lastTextBaseline) {
                Text(text.uppercased()).font(Bauhaus.Typo.section).tracking(1.6).foregroundStyle(Bauhaus.Palette.ink)
                Spacer(minLength: Bauhaus.Space.s)
                accessory
            }
            HRule(thickness: Bauhaus.Rule.thick)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionTitle where Accessory == EmptyView {
    init(_ text: String) { self.init(text) { EmptyView() } }
}

/// Wide square button: black (primary), blue (action), outlined (secondary), red (Pro).
struct BarButton: View {
    enum Kind { case primary, action, secondary, pro }
    let title: String
    var systemImage: String? = nil
    var kind: Kind = .primary
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Bauhaus.Space.s) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)) }
                Text(title.uppercased()).font(Bauhaus.Typo.button).tracking(1).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Bauhaus.Space.m)
            .frame(maxWidth: .infinity, minHeight: Bauhaus.tapTarget)
            .background(background)
            .overlay(Rectangle().stroke(isEnabled ? Bauhaus.Palette.ink : Bauhaus.Palette.inkDisabled, lineWidth: Bauhaus.Rule.regular))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        guard isEnabled else { return kind == .secondary ? Bauhaus.Palette.inkDisabled : Bauhaus.Palette.ground }
        switch kind {
        case .secondary: return Bauhaus.Palette.ink
        case .primary, .action, .pro: return Bauhaus.Palette.ground
        }
    }

    private var background: Color {
        guard isEnabled else { return kind == .secondary ? Bauhaus.Palette.ground : Bauhaus.Palette.inkDisabled }
        switch kind {
        case .primary: return Bauhaus.Palette.ink
        case .action: return Bauhaus.Palette.blue
        case .secondary: return Bauhaus.Palette.ground
        case .pro: return Bauhaus.Palette.red
        }
    }
}

/// Small square-cornered outlined button for inline actions.
struct TagButton: View {
    let title: String
    var systemImage: String? = nil
    var filled = false
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(Bauhaus.Typo.font(14, weight: .semibold, relativeTo: .footnote)).lineLimit(1)
            }
            .foregroundStyle(filled ? Bauhaus.Palette.ground : (isEnabled ? Bauhaus.Palette.ink : Bauhaus.Palette.inkDisabled))
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(filled ? Bauhaus.Palette.blue : Bauhaus.Palette.ground)
            .overlay(Rectangle().stroke(isEnabled ? Bauhaus.Palette.ink : Bauhaus.Palette.inkDisabled, lineWidth: Bauhaus.Rule.regular))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Adjoining outlined segments; the selected one is a blue field.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var identifierPrefix = "segment"

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                let selected = option.0 == selection
                Button { selection = option.0 } label: {
                    Text(option.1.uppercased())
                        .font(Bauhaus.Typo.button).tracking(0.8)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(selected ? Bauhaus.Palette.ground : Bauhaus.Palette.ink)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: Bauhaus.tapTarget)
                        .background(selected ? Bauhaus.Palette.blue : Bauhaus.Palette.ground)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.1)
                .accessibilityIdentifier("\(identifierPrefix)-\(option.1)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                if i < options.count - 1 { VRule() }
            }
        }
        .frame(height: Bauhaus.tapTarget)
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
    }
}

/// Text field in a 2 pt black frame.
struct BoxedTextField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font = Bauhaus.Typo.body

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(Bauhaus.Palette.ink)
            .padding(.horizontal, Bauhaus.Space.m - 4)
            .frame(minHeight: 48)
            .background(Bauhaus.Palette.ground)
            .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
            .autocorrectionDisabled()
    }
}

/// Square checkbox: a blue field with a white check glyph when on.
struct Checkbox: View {
    let label: String
    var systemImage: String? = nil
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Bauhaus.Space.m - 4) {
                ZStack {
                    (isOn ? Bauhaus.Palette.blue : Bauhaus.Palette.ground)
                    if isOn { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Bauhaus.Palette.ground) }
                }
                .frame(width: 24, height: 24)
                .overlay(Rectangle().stroke(isEnabled ? Bauhaus.Palette.ink : Bauhaus.Palette.inkDisabled, lineWidth: Bauhaus.Rule.regular))
                if let systemImage { Image(systemName: systemImage).frame(width: 22).foregroundStyle(Bauhaus.Palette.ink) }
                Text(label).font(Bauhaus.Typo.body).foregroundStyle(isEnabled ? Bauhaus.Palette.ink : Bauhaus.Palette.inkDisabled)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Bauhaus.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// White panel with the 2 pt frame.
struct Panel<Content: View>: View {
    var fill: Color = Bauhaus.Palette.ground
    let content: Content

    init(fill: Color = Bauhaus.Palette.ground, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
    }
}

/// A flat field of primary colour with a single SF Symbol, used as a row marker.
struct GlyphTile: View {
    let systemImage: String
    var fill: Color = Bauhaus.Palette.blue
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(fill == Bauhaus.Palette.yellow || fill == Bauhaus.Palette.ground ? Bauhaus.Palette.ink : Bauhaus.Palette.ground)
            .frame(width: size, height: size)
            .background(fill)
            .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
            .accessibilityHidden(true)
    }
}

extension View {
    /// White ground, black ink, Jost, light appearance.
    func bauhausScreen() -> some View {
        self.font(Bauhaus.Typo.body)
            .foregroundStyle(Bauhaus.Palette.ink)
            .background(Bauhaus.Palette.ground)
            .tint(Bauhaus.Palette.blue)
            .preferredColorScheme(.light)
    }

    @ViewBuilder
    func bauhausSheet() -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) {
            self.presentationCornerRadius(0).presentationBackground(Bauhaus.Palette.ground)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
