import SwiftUI

struct FooterStrip: View {
    let weather:    WeatherResponse?
    let postalDelivery: PostalDeliveryResponse?
    let postalDeliveryStale: Bool
    let nowPlaying: NowPlayingStore

    @State private var now = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var solar: (rise: Date?, set: Date?) { solarTimes(date: now) }

    private var sunText: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        guard let rise = solar.rise, let set = solar.set else { return "—" }
        return "\(df.string(from: rise)) – \(df.string(from: set))  ·  \(dayLengthText(rise: rise, set: set))"
    }

    private var postText: String {
        guard let dates = postalDelivery?.deliveryDates, !dates.isEmpty else {
            return postalDeliveryStale ? "Kunne ikke oppdatere" : "Laster…"
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "nb_NO")
        df.dateFormat = "EEE d. MMM"

        let labels = dates.prefix(3).map { date -> String in
            if Calendar.current.isDateInToday(date) { return "I dag" }
            if Calendar.current.isDateInTomorrow(date) { return "I morgen" }
            return df.string(from: date)
        }

        return labels.joined(separator: "  ·  ")
    }

    var body: some View {
        HStack(spacing: 0) {
            FooterCell(label: "POST", value: postText)
            footerDivider
            FooterCell(label: "SOL", value: sunText)
            footerDivider
            FooterCell(label: "POLLENVARSEL", value: "Bjørk  ·  Moderat")

            if nowPlaying.isPlaying {
                footerDivider
                NowPlayingCell(nowPlaying: nowPlaying)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onReceive(timer) { now = $0 }
    }

    private var footerDivider: some View {
        Theme.divider
            .opacity(0.9)
            .frame(width: 0.5, height: 18)
            .padding(.horizontal, 14)
    }
}

private struct FooterCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(1.6)
                .foregroundStyle(Theme.muted.opacity(0.9))
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.muted.opacity(0.96))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

private struct NowPlayingCell: View {
    let nowPlaying: NowPlayingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("SPILLES NÅ")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.muted.opacity(0.9))
            }
            HStack(spacing: 4) {
                Text(nowPlaying.title ?? "")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.muted.opacity(0.96))
                    .lineLimit(1)
                if let artist = nowPlaying.artist {
                    Text("·")
                        .foregroundStyle(Theme.dimmed)
                    Text(artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, Theme.hpad)
    }
}
