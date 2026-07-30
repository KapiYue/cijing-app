import SwiftUI
import UIKit

private struct AppTabBarHiddenKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var appTabBarHidden: Binding<Bool> {
        get { self[AppTabBarHiddenKey.self] }
        set { self[AppTabBarHiddenKey.self] = newValue }
    }
}

/// Shared visual tokens from the 390 × 844 interactive prototype.
enum CiJingTheme {
    static let purple = adaptive(light: 0x7651C9, dark: 0xB79AFF)
    static let purpleDark = adaptive(light: 0x5F3FAF, dark: 0xD1C0FF)
    static let purpleSoft = adaptive(light: 0xE9E0F8, dark: 0x33264A)
    static let canvas = adaptive(light: 0xF1EBF8, dark: 0x17131F)
    static let ink = adaptive(light: 0x26212D, dark: 0xF6F0FB)
    static let secondary = adaptive(light: 0x8A8490, dark: 0xB8B0C0)
    static let line = adaptive(light: 0xE2D8EC, dark: 0x463852)
    static let warm = adaptive(light: 0xE99B54, dark: 0xF3B16F)
    static let success = adaptive(light: 0x3FB781, dark: 0x68D9A7)
    static let danger = adaptive(light: 0xDB6B77, dark: 0xFF8C98)
    static let surface = adaptive(light: 0xFFFDFE, dark: 0x241D2C)
    static let surfaceElevated = adaptive(light: 0xF9F6FD, dark: 0x2B2235)
    static let surfaceMuted = adaptive(light: 0xF7F2FB, dark: 0x30263B)
    static let warmSoft = adaptive(light: 0xFFF1E4, dark: 0x3B2A24)
    static let shadow = adaptive(light: 0x423157, dark: 0x000000)

    // Compatibility names used by the existing reading and practice flows.
    static let green = purple
    static let lightGreen = purpleSoft
    static let paper = canvas

    static let pageGradient = LinearGradient(
        colors: [adaptive(light: 0xF6F1FB, dark: 0x211929), canvas],
        startPoint: .top,
        endPoint: .bottom
    )

    static let primaryGradient = LinearGradient(
        colors: [adaptive(light: 0x805BD2, dark: 0x8E68DD), adaptive(light: 0x6C45BD, dark: 0x6844B8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let featuredGradient = LinearGradient(
        colors: [adaptive(light: 0xF8F1FF, dark: 0x30233F), adaptive(light: 0xEADCF9, dark: 0x241A31)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: Int) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case projectDefault = "default"
    case system
    case light
    case dark

    static let projectDefaultColorScheme: ColorScheme = .light

    var id: String { rawValue }
    var title: String {
        switch self {
        case .projectDefault: "项目默认（浅色）"
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var subtitle: String {
        switch self {
        case .projectDefault: "使用项目代码设定的默认外观"
        case .system: "随 iPhone 的外观自动切换"
        case .light: "始终使用浅色外观"
        case .dark: "始终使用深色外观"
        }
    }
    var icon: String {
        switch self {
        case .projectDefault: "paintbrush"
        case .system: "iphone"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .projectDefault: Self.projectDefaultColorScheme
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func selection(for storedValue: String?) -> AppAppearance {
        AppAppearance(rawValue: storedValue ?? "") ?? .system
    }
}

/// Shared type scale for the app's readable 12–18 pt body hierarchy.
enum CiJingTypography {
    static let pageTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    static let sectionTitle = Font.system(size: 19, weight: .bold, design: .rounded)
    static let rowTitle = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 15)
    static let supporting = Font.system(size: 12)
    static let label = Font.system(size: 12, weight: .semibold)
    static let tab = Font.system(size: 12, weight: .semibold)
}

struct PaperBackground: View {
    var body: some View {
        ZStack {
            CiJingTheme.pageGradient
            Circle()
                .fill(CiJingTheme.purple.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 28)
                .offset(x: 150, y: -330)
        }
        .ignoresSafeArea()
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(CiJingTypography.pageTitle)
                    .tracking(-1.1)
                    .foregroundStyle(CiJingTheme.ink)
                Text(subtitle)
                    .font(CiJingTypography.body)
                    .foregroundStyle(CiJingTheme.secondary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 8)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 14 : 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 40 : 52)
            .padding(.horizontal, compact ? 16 : 20)
            .background(CiJingTheme.primaryGradient.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: compact ? 13 : 17, style: .continuous))
            .shadow(color: CiJingTheme.purpleDark.opacity(configuration.isPressed ? 0.12 : 0.24), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                LinearGradient(colors: [CiJingTheme.surface, CiJingTheme.surfaceElevated], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CiJingTheme.line.opacity(0.75)))
            .shadow(color: CiJingTheme.shadow.opacity(0.12), radius: 21, y: 10)
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var submitTitle: String? = nil
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CiJingTheme.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(CiJingTheme.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
            if let submitTitle {
                Button(submitTitle) { onSubmit?() }
                    .font(.caption.bold())
                    .foregroundStyle(CiJingTheme.purple)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(CiJingTypography.body)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(CiJingTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(CiJingTheme.line))
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack {
            Text(title).font(CiJingTypography.sectionTitle).foregroundStyle(CiJingTheme.ink)
            Spacer()
            if let detail { Text(detail).font(CiJingTypography.label).foregroundStyle(CiJingTheme.purple) }
        }
    }
}

extension View {
    func cijingCard(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}
