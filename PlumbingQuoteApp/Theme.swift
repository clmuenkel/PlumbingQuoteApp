import SwiftUI

enum AppTheme {
    static let bg = Color(hex: 0xFAF8F5)
    static let bgAlt = Color(hex: 0xF2F0EB)
    static let surface = Color(hex: 0xFFFFFF)
    static let surface2 = Color(hex: 0xF7F4EF)
    static let muted = Color(hex: 0x64748B)
    static let text = Color(hex: 0x1E293B)
    static let accent = Color(hex: 0x0B5394)
    static let accentLight = Color(hex: 0xC9DAF8)
    static let accentDark = Color(hex: 0x083D6F)

    static let success = Color(hex: 0x16A34A)
    static let warning = Color(hex: 0xEAB308)
    static let error = Color(hex: 0xDC2626)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
