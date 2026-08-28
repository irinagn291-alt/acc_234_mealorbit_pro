import SwiftUI
import UIKit

/// Onion ring: Infrastructure / UI.
/// Single colour accessor. Tokens live in the asset catalog; no other hex literals exist.
enum OrbitPalette {
    enum Token: String, Sendable {
        case background = "mlo_background"
        case surface = "mlo_surface"
        case ink = "mlo_ink"
        case accent = "mlo_accent"
        case muted = "mlo_muted"
    }

    static func color(_ token: Token) -> Color {
        Color(token.rawValue)
    }

    static func uiColor(_ token: Token) -> UIColor {
        UIColor(named: token.rawValue) ?? UIColor.black
    }
}

/// Onion ring: Infrastructure / UI.
/// Six-step type scale. Telemetry figures use SF Mono; prose uses SF Pro.
enum OrbitType: CaseIterable {
    case display
    case title
    case body
    case caption
    case figure
    case micro

    var font: Font {
        switch self {
        case .display:
            .system(.largeTitle, design: .monospaced).weight(.bold)
        case .title:
            .system(.title2, design: .default).weight(.semibold)
        case .body:
            .system(.body, design: .default)
        case .caption:
            .system(.caption, design: .default)
        case .figure:
            .system(.body, design: .monospaced).weight(.medium)
        case .micro:
            .system(.caption2, design: .monospaced)
        }
    }

    var uiFont: UIFont {
        let style: UIFont.TextStyle
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .display:
            style = .largeTitle
            design = .monospaced
        case .title:
            style = .title2
            design = .default
        case .body:
            style = .body
            design = .default
        case .caption:
            style = .caption1
            design = .default
        case .figure:
            style = .body
            design = .monospaced
        case .micro:
            style = .caption2
            design = .monospaced
        }
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: 0)
    }
}

enum OrbitSpace {
    static let unit: CGFloat = 8
    static let stack: CGFloat = 16
    static let inset: CGFloat = 16
    static let radius: CGFloat = 8
    static let tap: CGFloat = 44
}

enum OrbitMotion {
    static let duration: Double = 0.28

    static var curve: Animation {
        .easeInOut(duration: duration)
    }

    static func preferred<V: Equatable>(value: V, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : curve
    }
}

@MainActor
enum OrbitFigures {
    private static let energyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let macroFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func kcal(_ value: Double) -> String {
        energyFormatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }

    static func macro(_ value: Double) -> String {
        macroFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    static func energy(_ value: Double?) -> String {
        guard let value else { return "—" }
        return kcal(value)
    }

    static func nutrient(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return macro(value)
    }

    static func parseGrams(_ raw: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        guard let number = formatter.number(from: raw) else { return nil }
        return number.doubleValue
    }

    static func sanitiseGrams(_ raw: String) -> String {
        let separator = Locale.current.decimalSeparator ?? "."
        var result = ""
        var seenSeparator = false
        for character in raw {
            if character.isNumber {
                result.append(character)
            } else if String(character) == separator || character == "." || character == "," {
                if !seenSeparator {
                    result.append(contentsOf: separator)
                    seenSeparator = true
                }
            }
        }
        return result
    }
}

@MainActor
enum OrbitHaptics {
    static func commit() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Onion ring: Infrastructure / UI.
/// Optional local passcode stored via the vendored KeychainAccess-compatible API.
@MainActor
final class LocalPasscode {
    private let keychain = Keychain(service: "com.mealorbit.orbit")
    private let storageKey = "mlo.passcode"

    var value: String? {
        get { keychain[storageKey] }
        set { keychain[storageKey] = newValue }
    }
}
