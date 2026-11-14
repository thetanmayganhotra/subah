import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

struct Palette {
    let top: Color
    let mid: Color
    let bottom: Color
    let ink: Color
    let sub: Color
    let accent: Color
    let card: Color
    let dark: Bool

    static let dawn = Palette(top: Color(hex: 0xF9DCC4), mid: Color(hex: 0xF3C9C9), bottom: Color(hex: 0xCFC9EA),
                              ink: Color(hex: 0x4A3B47), sub: Color(hex: 0x4A3B47, opacity: 0.62), accent: Color(hex: 0xD9826B),
                              card: Color.white.opacity(0.42), dark: false)
    static let day = Palette(top: Color(hex: 0xDCEBF3), mid: Color(hex: 0xF7F0E4), bottom: Color(hex: 0xF8E4D0),
                             ink: Color(hex: 0x3D4A52), sub: Color(hex: 0x3D4A52, opacity: 0.62), accent: Color(hex: 0x6E9C8E),
                             card: Color.white.opacity(0.5), dark: false)
    static let dusk = Palette(top: Color(hex: 0xF3C8A2), mid: Color(hex: 0xDBA6B8), bottom: Color(hex: 0x958DBE),
                              ink: Color(hex: 0x3A2E45), sub: Color(hex: 0x3A2E45, opacity: 0.65), accent: Color(hex: 0x8A5FA8),
                              card: Color.white.opacity(0.36), dark: false)
    static let night = Palette(top: Color(hex: 0x1E2340), mid: Color(hex: 0x2C2F5E), bottom: Color(hex: 0x4A4479),
                               ink: Color(hex: 0xF3EAE2), sub: Color(hex: 0xF3EAE2, opacity: 0.62), accent: Color(hex: 0xE8B98A),
                               card: Color.white.opacity(0.08), dark: true)

    static func forDate(_ d: Date) -> Palette {
        switch Calendar.current.component(.hour, from: d) {
        case 5..<10: return dawn
        case 10..<17: return day
        case 17..<20: return dusk
        default: return night
        }
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.dawn }
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Font {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
}

struct SkyBackground: View {
    let palette: Palette
    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.top, palette.mid, palette.bottom], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(palette.dark ? 0.10 : 0.55), .clear], center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 520, height: 520)
                .offset(x: 120, y: -260)
            Circle()
                .fill(RadialGradient(colors: [palette.accent.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 440, height: 440)
                .offset(x: -170, y: 380)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 2), value: palette.dark)
    }
}

struct CardStyle: ViewModifier {
    @Environment(\.palette) var pal
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(pal.card))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(pal.ink.opacity(0.07), lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct PillButton: View {
    @Environment(\.palette) var pal
    let title: String
    var icon: String?
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)) }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(filled ? (pal.dark ? Color(hex: 0x2A2340) : .white) : pal.ink)
            .background(Capsule().fill(filled ? pal.accent : pal.ink.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// "Good morning" only when it actually is morning.
func timeGreeting(_ date: Date = Date(), tz: TimeZone = .current) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    switch cal.component(.hour, from: date) {
    case 4..<12: return "Good morning"
    case 12..<17: return "Good afternoon"
    case 17..<22: return "Good evening"
    default: return "Hello"
    }
}
