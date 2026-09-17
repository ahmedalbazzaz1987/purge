//
//  Theme.swift
//  Purge
//

import SwiftUI
import Combine

/// A stand-in for `@State`.
///
/// On current SDKs `@State` is a Swift macro, and the plugin that expands it
/// (`SwiftUIMacros`) ships with Xcode but **not** with the Command Line Tools.
/// Since Purge is meant to build with the Command Line Tools alone, it avoids
/// the macro entirely: `@StateObject private var flag = Local(false)` gives the
/// same per-view storage and the same `$flag.value` binding, using a property
/// wrapper that has no macro behind it.
final class Local<Value>: ObservableObject {
    @Published var value: Value
    init(_ initial: Value) { value = initial }
}

enum Theme {

    // Core palette — a cool graphite base with a single teal accent.
    static let accent      = Color(red: 0.24, green: 0.80, blue: 0.74)
    static let accentDeep  = Color(red: 0.12, green: 0.56, blue: 0.56)
    static let green       = Color(red: 0.32, green: 0.80, blue: 0.51)
    static let amber       = Color(red: 0.98, green: 0.72, blue: 0.30)
    static let red         = Color(red: 0.95, green: 0.42, blue: 0.40)

    static let sidebarBG   = Color(red: 0.086, green: 0.098, blue: 0.118)
    static let canvasBG    = Color(red: 0.063, green: 0.071, blue: 0.086)
    static let cardBG      = Color(red: 0.118, green: 0.133, blue: 0.157)
    static let cardStroke  = Color.white.opacity(0.07)
    static let hairline    = Color.white.opacity(0.06)

    static let textPrimary = Color(red: 0.93, green: 0.94, blue: 0.96)
    static let textMuted   = Color(red: 0.60, green: 0.64, blue: 0.70)
    static let textFaint   = Color(red: 0.42, green: 0.46, blue: 0.52)

    static let corner: CGFloat = 12
}

// MARK: - Card

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.cardBG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var wide: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.horizontal, wide ? 26 : 18)
            .padding(.vertical, 9)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Theme.textMuted

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Small pieces

struct RiskBadge: View {
    let risk: RiskTier

    var body: some View {
        Text(risk.label.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(risk.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(risk.color.opacity(0.15))
            )
            .help(risk.note)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textFaint)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }
}

/// A checkbox that does not fight the dark theme the way the system one does.
struct Tick: View {
    let on: Bool
    var mixed: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(on || mixed ? Theme.accent : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(on || mixed ? Theme.accent : Theme.textFaint, lineWidth: 1.4)
            )
            .overlay(
                Group {
                    if mixed {
                        Rectangle().fill(Color.black.opacity(0.8))
                            .frame(width: 8, height: 1.8)
                    } else if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.black.opacity(0.85))
                    }
                }
            )
            .frame(width: 15, height: 15)
    }
}

/// Disk usage ring used on the Smart Scan screen.
struct DiskRing: View {
    let fraction: Double
    let centerTop: String
    let centerBottom: String
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(0.004, min(fraction, 1)))
                .stroke(
                    AngularGradient(colors: [tint, Theme.accentDeep, tint],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: fraction)
            VStack(spacing: 2) {
                Text(centerTop)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(centerBottom)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(width: 168, height: 168)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
