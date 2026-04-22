import SwiftUI

struct StatusBarView: View {
    let api: APIClient
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var weekdayName: String {
        now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "nb_NO"))).capitalized
    }

    private var dateString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "nb_NO")
        df.dateFormat = "d. MMMM"
        return df.string(from: now)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: weekday + date
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(weekdayName) \(dateString)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center: clock
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)

            // Right: both T-bane directions
            BothDirections(transport: api.transport, stale: api.transportStale)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Theme.hpad)
        .padding(.vertical, 11)
        .onReceive(timer) { now = $0 }
    }
}

// MARK: - Both T-bane directions

private struct BothDirections: View {
    let transport: TransportResponse?
    let stale: Bool

    /// Next departure in each unique direction (up to 2)
    private var departures: [Departure] {
        guard let t = transport else { return [] }
        var seen: [String] = []
        var result: [Departure] = []
        for dep in t.departures.prefix(15) {
            if !seen.contains(dep.destination) {
                seen.append(dep.destination)
                result.append(dep)
            }
            if result.count == 2 { break }
        }
        return result
    }

    var body: some View {
        HStack(spacing: 12) {
            if departures.isEmpty {
                Text(stale ? "Ingen avganger" : "—")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dimmed)
            } else {
                ForEach(Array(departures.enumerated()), id: \.offset) { idx, dep in
                    HStack(spacing: 5) {
                        Text(dep.line)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Theme.lineColor(for: dep.line), in: RoundedRectangle(cornerRadius: 3))

                        Text(dep.destination)
                            .font(.system(size: 14))
                            .foregroundStyle(stale ? Theme.dimmed : Theme.muted.opacity(0.9))
                            .lineLimit(1)

                        Text(dep.minutesText)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(stale ? Theme.dimmed : Theme.text)
                            .monospacedDigit()
                    }

                    if idx == 0 && departures.count > 1 {
                        Theme.divider.frame(width: 0.5, height: 16)
                    }
                }
            }
        }
    }
}
