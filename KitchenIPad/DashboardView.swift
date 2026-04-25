import SwiftUI
import EventKit

struct DashboardView: View {
    @State private var api        = APIClient.shared
    @State private var nowPlaying = NowPlayingStore()
    @State private var calStore   = CalendarStore()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    StatusBarView(api: api)
                    HLine()

                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            TodaySituationCard(api: api, calStore: calStore)
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            HLine()

                            UtilityCornerControls()
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(.leading, Theme.pad - 1)
                                .padding(.trailing, Theme.pad - 2)
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                                .frame(height: utilityControlsHeight(geo), alignment: .topLeading)
                        }
                        .frame(width: todayColumnWidth(geo), alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)

                        VLine()

                        CalendarCard(calStore: calStore)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: .infinity)

                    HLine()

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
            await calStore.requestAccess()
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if calStore.authorized { await calStore.fetch() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { if calStore.authorized { await calStore.fetch() } }
        }
        .onAppear { nowPlaying.startObserving() }
    }

    private func todayColumnWidth(_ geo: GeometryProxy) -> CGFloat {
        geo.size.width * 0.32
    }

    private func utilityControlsHeight(_ geo: GeometryProxy) -> CGFloat {
        min(max(140, geo.size.height * 0.18), 180)
    }
}
