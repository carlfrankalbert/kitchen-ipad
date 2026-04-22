import SwiftUI

struct WeatherCard: View {
    let api: APIClient

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let w = api.weather {
                WeatherContent(weather: w, stale: api.weatherStale)
            } else {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dimmed)
                    .padding(Theme.pad)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeatherContent: View {
    let weather: WeatherResponse
    let stale: Bool

    private var todayHighLow: (high: Int, low: Int)? {
        let cal = Calendar.current
        let isoFull  = ISO8601DateFormatter()
        isoFull.formatOptions  = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        let temps: [Double] = weather.hourly.compactMap { h in
            let d = isoFull.date(from: h.time) ?? isoBasic.date(from: h.time)
            guard let date = d, cal.isDateInToday(date) else { return nil }
            return h.temperature
        }
        guard !temps.isEmpty else { return nil }
        return (Int((temps.max() ?? 0).rounded()), Int((temps.min() ?? 0).rounded()))
    }

    /// Condition + wind sentence (no clothing — that's shown separately with emojis).
    private var conditionSentence: String {
        let temp   = weather.current.temperature
        let wind   = weather.current.windSpeed
        let symbol = weather.current.symbolCode

        let feeling: String = {
            switch temp {
            case ..<0:    return "og bitende kaldt"
            case 0..<5:   return "og kaldt"
            case 5..<10:  return "og friskt"
            case 10..<15: return "og kjølig"
            case 15..<20: return "og mildt"
            case 20..<25: return "og varmt"
            default:      return "og hett"
            }
        }()

        let windText: String = {
            switch wind {
            case ..<2:    return "Vindstille."
            case 2..<5:   return "Svak vind, \(Int(wind.rounded())) m/s."
            case 5..<10:  return "Lett bris, \(Int(wind.rounded())) m/s."
            case 10..<15: return "Frisk bris, \(Int(wind.rounded())) m/s."
            default:      return "Sterk vind, \(Int(wind.rounded())) m/s."
            }
        }()

        return "\(symbol.weatherDescription) \(feeling). \(windText)"
    }

    private var clothing: [ClothingItem] {
        clothingItems(
            temp:          weather.current.temperature,
            precipitation: weather.current.precipitation,
            windSpeed:     weather.current.windSpeed,
            symbolCode:    weather.current.symbolCode
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Large temperature + icon + H/L
            HStack(alignment: .top, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: weather.current.symbolCode.weatherSFSymbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 44))

                    Text("\(Int(weather.current.temperature.rounded()))°")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(stale ? Theme.dimmed : Theme.text)
                }

                Spacer(minLength: 6)

                if let hl = todayHighLow {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("↑ \(hl.high)°")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.infoBlue)
                        Text("↓ \(hl.low)°")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.infoBlue.opacity(0.78))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Theme.infoBlueSoft.opacity(0.7), in: Capsule())
                    .padding(.top, 3)
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // Condition + wind sentence
            Text(conditionSentence)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(stale ? Theme.dimmed : Theme.muted)
                .lineLimit(1)
                .lineSpacing(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 7)

            HLine()

            // Clothing with emojis
            if !clothing.isEmpty {
                Text("ANTREKK").label()
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 5)
                    .padding(.bottom, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(clothing) { item in
                            HStack(spacing: 3) {
                                Text(item.emoji)
                                    .font(.system(size: 24))
                                Text(item.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.divider.opacity(0.48), in: Capsule())
                        }
                    }
                    .padding(.horizontal, Theme.pad)
                }
                .padding(.bottom, 5)
            }
        }
    }
}

// MARK: - Flow layout (kept for potential reuse)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
