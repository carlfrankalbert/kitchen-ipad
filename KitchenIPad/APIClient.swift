import Foundation
import Observation

@Observable
@MainActor
final class APIClient {
    static let shared = APIClient()

    var weather:       WeatherResponse?
    var transport:     TransportResponse?
    var postalDelivery: PostalDeliveryResponse?
    var weatherStale   = false
    var transportStale = false
    var postalDeliveryStale = false

    private var gaustadStopId: String? = nil

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["ET-Client-Name": "carlfrankalbert-kitchenipad"]
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Weather via Yr.no (no auth)

    func fetchWeather() async {
        // Gaustad / Oslo coordinates
        let url = URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=59.9318&lon=10.7154")!
        var req = URLRequest(url: url)
        req.setValue("KitchenIPad/1.0 carlfrankalbert@gmail.com", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await session.data(for: req)
            let yr = try JSONDecoder().decode(YrResponse.self, from: data)
            weather = yr.toWeatherResponse()
            weatherStale = false
        } catch {
            weatherStale = true
        }
    }

    // MARK: - Transport via Entur (no auth)

    func fetchTransport() async {
        do {
            if gaustadStopId == nil {
                gaustadStopId = try await findStopId(for: "Gaustad")
            }
            guard let stopId = gaustadStopId else {
                transportStale = true
                return
            }
            let departures = try await fetchDepartures(stopId: stopId)
            transport = TransportResponse(
                stopName: "Gaustad",
                departures: departures,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            transportStale = false
        } catch {
            transportStale = true
        }
    }

    // MARK: - Postal delivery via Posten (no auth)

    func fetchPostalDelivery(postalCode: String = "0373") async {
        let url = URL(
            string: "https://www.posten.no/levering-av-post/_/service/no.posten.website/delivery-days?postalCode=\(postalCode)"
        )!
        do {
            let (data, _) = try await session.data(from: url)
            postalDelivery = try JSONDecoder().decode(PostalDeliveryResponse.self, from: data)
            postalDeliveryStale = false
        } catch {
            postalDeliveryStale = true
        }
    }

    private func findStopId(for name: String) async throws -> String? {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let url = URL(string: "https://api.entur.io/geocoder/v1/autocomplete?text=\(encoded)&lang=no&layers=venue&size=5")!
        let (data, _) = try await session.data(from: url)
        let geo = try JSONDecoder().decode(EnturGeocoderResponse.self, from: data)
        return geo.features.first { $0.properties.id.contains("StopPlace") }?.properties.id
    }

    private func fetchDepartures(stopId: String) async throws -> [Departure] {
        let graphQL = """
        { "query": "{ stopPlace(id: \\"\(stopId)\\") { estimatedCalls(timeRange: 7200 numberOfDepartures: 20) { realtime expectedDepartureTime destinationDisplay { frontText } serviceJourney { journeyPattern { line { publicCode transportMode } } } } } }" }
        """
        var req = URLRequest(url: URL(string: "https://api.entur.io/journey-planner/v3/graphql")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = graphQL.data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        let resp = try JSONDecoder().decode(EnturJourneyResponse.self, from: data)
        return (resp.data?.stopPlace?.estimatedCalls ?? [])
            .filter { $0.serviceJourney?.journeyPattern?.line.transportMode == "metro" }
            .map { call in
                Departure(
                    line:          call.serviceJourney?.journeyPattern?.line.publicCode ?? "T",
                    destination:   call.destinationDisplay?.frontText ?? "",
                    departureTime: call.expectedDepartureTime,
                    realtime:      call.realtime ?? false,
                    delayed:       false,
                    delayMinutes:  0,
                    cancelled:     false,
                    transportMode: "metro"
                )
            }
    }
}

// MARK: - Yr.no models

struct YrResponse: Codable {
    let properties: YrProperties
}
struct YrProperties: Codable {
    let timeseries: [YrTimestep]
}
struct YrTimestep: Codable {
    let time: String
    let data: YrData
}
struct YrData: Codable {
    let instant:    YrInstant
    let next1Hours: YrPeriod?
    let next6Hours: YrPeriod?
    enum CodingKeys: String, CodingKey {
        case instant
        case next1Hours = "next_1_hours"
        case next6Hours = "next_6_hours"
    }
}
struct YrInstant: Codable {
    let details: YrInstantDetails
}
struct YrInstantDetails: Codable {
    let airTemperature: Double
    let windSpeed:      Double
    enum CodingKeys: String, CodingKey {
        case airTemperature = "air_temperature"
        case windSpeed      = "wind_speed"
    }
}
struct YrPeriod: Codable {
    let summary: YrSummary
    let details: YrPeriodDetails
}
struct YrSummary: Codable {
    let symbolCode: String
    enum CodingKeys: String, CodingKey { case symbolCode = "symbol_code" }
}
struct YrPeriodDetails: Codable {
    let precipitationAmount: Double?
    enum CodingKeys: String, CodingKey { case precipitationAmount = "precipitation_amount" }
}

extension YrResponse {
    func toWeatherResponse() -> WeatherResponse {
        let ts     = properties.timeseries
        let first  = ts.first
        let period = first?.data.next1Hours ?? first?.data.next6Hours
        let current = WeatherCurrent(
            temperature:   first?.data.instant.details.airTemperature ?? 0,
            feelsLike:     nil,
            windSpeed:     first?.data.instant.details.windSpeed ?? 0,
            precipitation: period?.details.precipitationAmount ?? 0,
            symbolCode:    period?.summary.symbolCode ?? "cloudy"
        )
        let hourly: [WeatherHourly] = ts.prefix(24).map { step in
            let p = step.data.next1Hours ?? step.data.next6Hours
            return WeatherHourly(
                time:          step.time,
                temperature:   step.data.instant.details.airTemperature,
                precipitation: p?.details.precipitationAmount ?? 0,
                symbolCode:    p?.summary.symbolCode ?? "cloudy"
            )
        }
        return WeatherResponse(current: current, hourly: hourly, updatedAt: first?.time ?? "")
    }
}

// MARK: - Entur models

struct EnturGeocoderResponse: Codable {
    let features: [EnturFeature]
}
struct EnturFeature: Codable {
    let properties: EnturFeatureProps
}
struct EnturFeatureProps: Codable {
    let id:    String
    let name:  String?
    let label: String?
}

struct EnturJourneyResponse: Codable {
    let data: EnturData?
}
struct EnturData: Codable {
    let stopPlace: EnturStopPlace?
}
struct EnturStopPlace: Codable {
    let estimatedCalls: [EnturCall]
}
struct EnturCall: Codable {
    let realtime:            Bool?
    let expectedDepartureTime: String
    let destinationDisplay:  EnturDestination?
    let serviceJourney:      EnturServiceJourney?
}
struct EnturDestination: Codable {
    let frontText: String
}
struct EnturServiceJourney: Codable {
    let journeyPattern: EnturJourneyPattern?
}
struct EnturJourneyPattern: Codable {
    let line: EnturLine
}
struct EnturLine: Codable {
    let publicCode:    String
    let transportMode: String?
}
