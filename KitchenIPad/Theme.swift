import SwiftUI

enum Theme {
    // MARK: - Colors
    static let bg      = Color(hex: 0xD9D2C0)   // warm beige background
    static let text    = Color(hex: 0x1C1917)   // near-black
    static let muted   = Color(hex: 0x6E6660)   // warm gray, improved readability
    static let dimmed  = Color(hex: 0x958E86)   // secondary text
    static let accent  = Color(hex: 0xC2410C)   // today orange
    static let infoBlue = Color(hex: 0x0B5CAD)
    static let infoBlueSoft = Color(hex: 0xDCEBFA)
    static let green   = Color(hex: 0x15803D)
    static let red     = Color(hex: 0xDC2626)
    static let divider = Color(hex: 0xACA495)   // subtle but clearer divider line

    // MARK: - Spacing
    static let pad: CGFloat  = 18   // inner card padding
    static let hpad: CGFloat = 20   // horizontal page margin

    // MARK: - Transport line colors
    static func lineColor(for line: String) -> Color {
        switch line {
        case "1", "4", "6": return Color(hex: 0x0352A0)
        case "2", "3":       return Color(hex: 0xF26522)
        case "5":            return Color(hex: 0x00A857)
        default:             return accent
        }
    }
}

// MARK: - Reusable dividers

extension View {
    func hLine() -> some View {
        Theme.divider.frame(height: 0.6).frame(maxWidth: .infinity)
    }
}

struct VLine: View {
    var body: some View {
        Theme.divider.frame(width: 0.6).frame(maxHeight: .infinity)
    }
}

struct HLine: View {
    var body: some View {
        Theme.divider.frame(height: 0.6).frame(maxWidth: .infinity)
    }
}

// MARK: - Typography helpers

extension View {
    /// Small-caps label: 9pt semibold, tracked
    func label() -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .kerning(1.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted.opacity(0.96))
    }

    /// Small-caps label in accent color (for today)
    func accentLabel() -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .kerning(1.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.accent)
    }
}

// MARK: - Color init

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Solar calculation (for footer)

func solarTimes(lat: Double = 59.9318, lon: Double = 10.7154, date: Date = Date()) -> (rise: Date?, set: Date?) {
    let cal = Calendar(identifier: .gregorian)
    guard let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) else { return (nil, nil) }

    let B     = (360.0 / 365.0 * (Double(dayOfYear) - 81)) * .pi / 180
    let decl  = 23.45 * sin(B) * .pi / 180
    let cosHA = (-sin(0.8333 * .pi / 180) - sin(lat * .pi / 180) * sin(decl)) /
                (cos(lat * .pi / 180) * cos(decl))
    guard cosHA >= -1 && cosHA <= 1 else { return (nil, nil) }

    let HA   = acos(cosHA) * 180 / .pi
    let eot  = 9.87 * sin(2 * B) - 7.53 * cos(B) - 1.5 * sin(B)
    let noon = 12.0 - lon / 15.0 - eot / 60.0
    let tz   = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600.0

    func toDate(_ utcH: Double) -> Date? {
        let local = utcH + tz
        let h = ((Int(local) % 24) + 24) % 24
        let m = Int((local - floor(local)) * 60)
        var c = cal.dateComponents([.year, .month, .day], from: date)
        c.hour = h; c.minute = m; c.second = 0
        return cal.date(from: c)
    }

    return (toDate(noon - HA / 15.0), toDate(noon + HA / 15.0))
}

func dayLengthText(rise: Date, set: Date) -> String {
    let secs = set.timeIntervalSince(rise)
    let h    = Int(secs / 3600)
    let m    = Int((secs.truncatingRemainder(dividingBy: 3600)) / 60)
    return "daglengde \(h) t \(m) min"
}

// MARK: - Norwegian year (2026 → "tjuetjueseks")

func norwegianYear(from date: Date = Date()) -> String {
    let year    = Calendar.current.component(.year, from: date)
    let lastTwo = year % 100
    return "tjue" + norwegianSmallNumber(lastTwo)
}

private func norwegianSmallNumber(_ n: Int) -> String {
    let ones = ["", "en", "to", "tre", "fire", "fem",
                "seks", "sju", "åtte", "ni", "ti",
                "elleve", "tolv", "tretten", "fjorten", "femten",
                "seksten", "sytten", "atten", "nitten"]
    if n < 20 { return ones[n] }
    let tens = ["", "", "tjue", "tretti", "førti", "femti"]
    let t = tens[n / 10], r = n % 10
    return r == 0 ? t : t + ones[r]
}
