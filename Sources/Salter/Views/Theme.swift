import AppKit
import SwiftUI

/// Linear-style tokens; each resolves per appearance (dark / light).
enum Theme {
    static let bg = dynamic(dark: 0x0f1011, light: 0xffffff)
    static let panel = dynamic(dark: 0x141517, light: 0xf7f7f8)
    static let line = dynamic(dark: 0x23252a, light: 0xe6e6e8)
    static let selection = dynamic(dark: 0x1f2024, light: 0xececef)
    static let text = dynamic(dark: 0xededed, light: 0x1b1c1f)
    static let text2 = dynamic(dark: 0x8a8f98, light: 0x6b6f76)
    static let text3 = dynamic(dark: 0x62666d, light: 0x9a9da3)
    static let accent = dynamic(dark: 0x5e6ad2, light: 0x5e6ad2)
    static let ok = dynamic(dark: 0x4cb782, light: 0x2f9e69)
    static let warn = dynamic(dark: 0xf2c94c, light: 0xc99a12)
    static let err = dynamic(dark: 0xeb5757, light: 0xd64545)
    static let info = dynamic(dark: 0x6b9bd2, light: 0x3d73b0)
    static let logText = dynamic(dark: 0xc9cbcf, light: 0x1b1c1f)

    static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

/// Thin-bordered secondary button.
struct QuietButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var tint: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration, height: height, tint: tint)
    }

    private struct QuietButton: View {
        let configuration: Configuration
        let height: CGFloat
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: height < 28 ? 12 : 12.5))
                .foregroundStyle(tint)
                .padding(.horizontal, height < 28 ? 8 : 12)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(configuration.isPressed || hovering ? Theme.selection : Color.clear)
                )
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

/// Square 28×28 icon button with the same thin border.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text2)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? Theme.selection : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
            .contentShape(Rectangle())
    }
}

/// The single filled action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration)
    }

    private struct PrimaryButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                .brightness(configuration.isPressed ? -0.08 : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
        }
    }
}

/// Borderless text/icon button used in toolbars and the menu bar.
struct PlainTextButtonStyle: ButtonStyle {
    var color: Color = Theme.text2

    func makeBody(configuration: Configuration) -> some View {
        PlainTextButton(configuration: configuration, color: color)
    }

    private struct PlainTextButton: View {
        let configuration: Configuration
        let color: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(hovering ? Theme.text : color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering || configuration.isPressed ? Theme.selection : Color.clear))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text3)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
    }
}

/// Plain text field with the thin border.
struct FieldStyle: ViewModifier {
    var monospaced = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
    }
}

extension View {
    func fieldStyle(monospaced: Bool = false) -> some View { modifier(FieldStyle(monospaced: monospaced)) }
}
