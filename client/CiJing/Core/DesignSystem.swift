import SwiftUI

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
    static let purple = Color(red: 118 / 255, green: 81 / 255, blue: 201 / 255)
    static let purpleDark = Color(red: 95 / 255, green: 63 / 255, blue: 175 / 255)
    static let purpleSoft = Color(red: 233 / 255, green: 224 / 255, blue: 248 / 255)
    static let canvas = Color(red: 241 / 255, green: 235 / 255, blue: 248 / 255)
    static let ink = Color(red: 38 / 255, green: 33 / 255, blue: 45 / 255)
    static let secondary = Color(red: 138 / 255, green: 132 / 255, blue: 144 / 255)
    static let line = Color(red: 226 / 255, green: 216 / 255, blue: 236 / 255)
    static let warm = Color(red: 233 / 255, green: 155 / 255, blue: 84 / 255)
    static let success = Color(red: 63 / 255, green: 183 / 255, blue: 129 / 255)
    static let danger = Color(red: 219 / 255, green: 107 / 255, blue: 119 / 255)

    // Compatibility names used by the existing reading and practice flows.
    static let green = purple
    static let lightGreen = purpleSoft
    static let paper = canvas

    static let pageGradient = LinearGradient(
        colors: [Color(red: 246 / 255, green: 241 / 255, blue: 251 / 255), canvas],
        startPoint: .top,
        endPoint: .bottom
    )

    static let primaryGradient = LinearGradient(
        colors: [Color(red: 128 / 255, green: 91 / 255, blue: 210 / 255), Color(red: 108 / 255, green: 69 / 255, blue: 189 / 255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
                LinearGradient(colors: [.white.opacity(0.94), Color(red: 249 / 255, green: 246 / 255, blue: 253 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CiJingTheme.line.opacity(0.75)))
            .shadow(color: Color(red: 66 / 255, green: 49 / 255, blue: 87 / 255).opacity(0.09), radius: 21, y: 10)
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
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
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
