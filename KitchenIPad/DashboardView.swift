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
                    VStack(spacing: 0) {
                        // Calendar stays full width for better readability
                        CalendarCard()
                            .frame(height: calendarHeight(geo))

                        HLine()

                        // Right side is dedicated to menu down to footer.
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                WeatherCard(api: api)
                                    .frame(height: weatherHeight(geo), alignment: .topLeading)

                                Spacer(minLength: 0)
                                HLine()

                                HStack(alignment: .top, spacing: 0) {
                                    ShoppingCard()
                                        .frame(maxWidth: .infinity)
                                    VLine()
                                    TodoCard()
                                        .frame(maxWidth: .infinity)
                                }
                                .frame(height: quickListsHeight(geo))
                            }
                            .frame(width: leftColumnWidth(geo), alignment: .topLeading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)

                            VLine()

                            MealPlanCard()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)

                    HLine()

                    // ── Footer info strip ───────────────────────────────
                    FooterStrip(
                        weather: api.weather,
                        postalDelivery: api.postalDelivery,
                        postalDeliveryStale: api.postalDeliveryStale,
                        nowPlaying: nowPlaying
                    )
                }
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .task {
            await api.fetchWeather()
            await api.fetchTransport()
            await api.fetchPostalDelivery()
        }
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(21600))
                await api.fetchPostalDelivery()
            }
        }
        .onAppear { nowPlaying.startObserving() }
    }

    private func calendarHeight(_ geo: GeometryProxy) -> CGFloat {
        max(200, geo.size.height * 0.145)
    }

    private func weatherHeight(_ geo: GeometryProxy) -> CGFloat {
        max(170, geo.size.height * 0.15)
    }

    private func leftColumnWidth(_ geo: GeometryProxy) -> CGFloat {
        geo.size.width * 0.35
    }

    private func quickListsHeight(_ geo: GeometryProxy) -> CGFloat {
        max(150, geo.size.height * 0.14)
    }
}

// MARK: - Footer info strip

private struct FooterStrip: View {
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

            // Now Playing — only shown when music is active
            if nowPlaying.isPlaying {
                footerDivider
                NowPlayingCell(nowPlaying: nowPlaying)
            }
        }
        .frame(maxWidth: .infinity)
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
        VStack(alignment: .center, spacing: 2) {
            Text(label).label()
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text)
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
