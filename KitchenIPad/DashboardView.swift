import SwiftUI

struct DashboardView: View {
    @State private var api        = APIClient.shared
    @State private var nowPlaying = NowPlayingStore()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Status bar ──────────────────────────────────────
                    StatusBarView(api: api)
                    HLine()

                    // ── Main content ────────────────────────────────────
                    HStack(alignment: .top, spacing: 0) {

                        // LEFT: calendar (week grid + today events) + lists
                        VStack(spacing: 0) {
                            CalendarCard()
                                .frame(maxHeight: .infinity)

                            HLine()

                            // Shopping + Todo under calendar
                            HStack(alignment: .top, spacing: 0) {
                                ShoppingCard()
                                    .frame(maxWidth: .infinity)
                                VLine()
                                TodoCard()
                                    .frame(maxWidth: .infinity)
                            }
                            .frame(height: listsHeight(geo))
                        }
                        .frame(width: leftWidth(geo))

                        VLine()

                        // RIGHT: bigger weather + meal plan (fills to footer)
                        VStack(spacing: 0) {
                            WeatherCard(api: api)
                            HLine()
                            MealPlanCard()
                                .frame(maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)

                    HLine()

                    // ── Footer info strip ───────────────────────────────
                    FooterStrip(weather: api.weather, nowPlaying: nowPlaying)
                }
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .task { await api.fetchWeather(); await api.fetchTransport() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                await api.fetchWeather()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await api.fetchTransport()
            }
        }
        .onAppear { nowPlaying.startObserving() }
    }

    private func leftWidth(_ geo: GeometryProxy) -> CGFloat {
        geo.size.width * 0.58
    }

    private func listsHeight(_ geo: GeometryProxy) -> CGFloat {
        geo.size.height * 0.24
    }
}

// MARK: - Footer info strip

private struct FooterStrip: View {
    let weather:    WeatherResponse?
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

    private var updateTime: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: now)
    }

    var body: some View {
        HStack(spacing: 0) {
            FooterCell(label: "SØPPELTØMMING", value: "Tirsdag 28. april  ·  Restavfall")
            footerDivider
            FooterCell(label: "PAPIR", value: "Fredag 9. mai  ·  Papp og papir")
            footerDivider
            FooterCell(label: "SOL", value: sunText)
            footerDivider
            FooterCell(label: "POLLENVARSEL", value: "Bjørk  ·  Moderat")

            // Now Playing — only shown when music is active
            if nowPlaying.isPlaying {
                footerDivider
                NowPlayingCell(nowPlaying: nowPlaying)
            }

            Spacer()

            Text("Oppdatert \(updateTime)")
                .font(.system(size: 9))
                .foregroundStyle(Theme.dimmed)
                .padding(.trailing, Theme.hpad)
        }
        .padding(.vertical, 9)
        .onReceive(timer) { now = $0 }
    }

    private var footerDivider: some View {
        Theme.divider
            .frame(width: 0.5, height: 24)
            .padding(.horizontal, 16)
    }
}

private struct FooterCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).label()
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .padding(.leading, Theme.hpad)
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
                Text("SPILLES NÅ").label()
            }
            HStack(spacing: 4) {
                Text(nowPlaying.title ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let artist = nowPlaying.artist {
                    Text("·")
                        .foregroundStyle(Theme.dimmed)
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, Theme.hpad)
    }
}
