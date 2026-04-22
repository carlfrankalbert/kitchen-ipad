import Foundation

// MARK: - Weather

struct WeatherResponse: Codable {
    let current: WeatherCurrent
    let hourly:  [WeatherHourly]
    let updatedAt: String
}

struct WeatherCurrent: Codable {
    let temperature:  Double
    let feelsLike:    Double?
    let windSpeed:    Double
    let precipitation: Double
    let symbolCode:   String
}

struct WeatherHourly: Codable {
    let time:          String
    let temperature:   Double
    let precipitation: Double
    let symbolCode:    String
}

// MARK: - Transport

struct TransportResponse: Codable {
    let stopName:   String
    let departures: [Departure]
    let updatedAt:  String
}

struct Departure: Codable, Identifiable {
    var id: String { "\(line)-\(destination)-\(departureTime)" }
    let line:          String
    let destination:   String
    let departureTime: String
    let realtime:      Bool
    let delayed:       Bool
    let delayMinutes:  Int
    let cancelled:     Bool
    let transportMode: String

    var minutesUntil: Int {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: departureTime) { return max(0, Int(d.timeIntervalSinceNow / 60)) }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: departureTime) { return max(0, Int(d.timeIntervalSinceNow / 60)) }
        return 0
    }

    var minutesText: String {
        let m = minutesUntil
        return m <= 0 ? "Nå" : "\(m) min"
    }
}

// MARK: - Postal delivery (Posten)

struct PostalDeliveryResponse: Codable {
    let deliveryDatesRaw: [String]

    enum CodingKeys: String, CodingKey {
        case deliveryDatesRaw = "delivery_dates"
    }

    var deliveryDates: [Date] {
        deliveryDatesRaw.compactMap { Self.dateFormatter.date(from: $0) }
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Europe/Oslo")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

// MARK: - Local meal plan (stored on device)

struct LocalMeal: Codable, Identifiable {
    var id   = UUID()
    var name:  String
    var emoji: String
    var note:  String?  // "Borte", "Takeaway", "Rester"
}

struct LocalDayPlan: Codable, Identifiable {
    var id      = UUID()
    var weekday: Int    // 1 = Monday … 7 = Sunday
    var meal:    LocalMeal?
}

// MARK: - Weekday helpers

let weekdayNames: [Int: String] = [
    1: "Man", 2: "Tir", 3: "Ons", 4: "Tor", 5: "Fre", 6: "Lør", 7: "Søn"
]

let weekdayNamesFull: [Int: String] = [
    1: "Mandag", 2: "Tirsdag", 3: "Onsdag", 4: "Torsdag",
    5: "Fredag", 6: "Lørdag", 7: "Søndag"
]

func norwegianWeekdayIndex(for date: Date, calendar: Calendar = .current) -> Int {
    let weekday = calendar.component(.weekday, from: date)
    return weekday == 1 ? 7 : weekday - 1
}

func currentWeekday(from date: Date = Date()) -> Int {
    norwegianWeekdayIndex(for: date)
}

// MARK: - Weather helpers

extension String {
    var weatherSFSymbol: String {
        switch self {
        case _ where contains("clearsky"):          return "sun.max.fill"
        case _ where contains("fair"):              return "cloud.sun.fill"
        case _ where contains("partlycloudy"):      return "cloud.sun.fill"
        case _ where contains("cloudy"):            return "cloud.fill"
        case _ where contains("heavyrain"):         return "cloud.heavyrain.fill"
        case _ where contains("lightrain"):         return "cloud.drizzle.fill"
        case _ where contains("rain"):              return "cloud.rain.fill"
        case _ where contains("sleet"):             return "cloud.sleet.fill"
        case _ where contains("snow"):              return "cloud.snow.fill"
        case _ where contains("fog"):               return "cloud.fog.fill"
        case _ where contains("thunder"):           return "cloud.bolt.rain.fill"
        default:                                    return "cloud.fill"
        }
    }

    var weatherDescription: String {
        switch self {
        case _ where contains("clearsky"):      return "Klarvær"
        case _ where contains("fair"):          return "Lettskyet"
        case _ where contains("partlycloudy"): return "Delvis skyet"
        case _ where contains("cloudy"):       return "Skyet"
        case _ where contains("heavyrain"):    return "Kraftig regn"
        case _ where contains("lightrain"):    return "Lett regn"
        case _ where contains("rain"):         return "Regn"
        case _ where contains("sleet"):        return "Sludd"
        case _ where contains("heavysnow"):    return "Kraftig snø"
        case _ where contains("snow"):         return "Snø"
        case _ where contains("fog"):          return "Tåke"
        case _ where contains("thunder"):      return "Torden"
        default:                               return "Skyet"
        }
    }
}

// MARK: - Clothing recommendation

struct ClothingItem: Identifiable {
    let id    = UUID()
    let emoji: String
    let label: String
}

func clothingItems(temp: Double, precipitation: Double, windSpeed: Double, symbolCode: String) -> [ClothingItem] {
    var items: [ClothingItem] = []
    let isRaining = precipitation > 0.5 || symbolCode.contains("rain") || symbolCode.contains("sleet")
    let isSnowing = symbolCode.contains("snow")
    let isSunny   = symbolCode.contains("clearsky") || symbolCode.contains("fair")

    if temp < 0 {
        items.append(.init(emoji: "🧥", label: "Vinterjakke"))
        items.append(.init(emoji: "🧤", label: "Lue & votter"))
        items.append(.init(emoji: "🧣", label: "Skjerf"))
    } else if temp < 5 {
        items.append(.init(emoji: "🧥", label: "Varm jakke"))
        items.append(.init(emoji: "🧢", label: "Lue"))
    } else if temp < 12 {
        items.append(.init(emoji: "🧥", label: "Lett jakke"))
        items.append(.init(emoji: "👕", label: "Genser"))
    } else if temp < 18 {
        items.append(.init(emoji: "👕", label: "Genser"))
    } else {
        items.append(.init(emoji: "👕", label: "T-skjorte"))
    }

    if isRaining {
        items.append(.init(emoji: "🌧️", label: "Regnjakke"))
        items.append(.init(emoji: "🥾", label: "Støvler"))
    }

    if isSnowing {
        items.append(.init(emoji: "❄️", label: "Snøutstyr"))
    }

    if windSpeed > 8 && !isRaining {
        items.append(.init(emoji: "💨", label: "Vindjakke"))
    }

    if isSunny && temp > 15 {
        items.append(.init(emoji: "🕶️", label: "Solbriller"))
    }

    return items
}

// MARK: - Meal emoji

func mealEmoji(for name: String) -> String {
    let l = name.lowercased()
    if l.contains("pizza")                                         { return "🍕" }
    if l.contains("pasta") || l.contains("spaghetti") || l.contains("bolognese") { return "🍝" }
    if l.contains("taco")                                          { return "🌮" }
    if l.contains("sushi")                                         { return "🍣" }
    if l.contains("suppe")                                         { return "🍲" }
    if l.contains("salat")                                         { return "🥗" }
    if l.contains("burger")                                        { return "🍔" }
    if l.contains("kylling") || l.contains("chicken")             { return "🍗" }
    if l.contains("laks") || l.contains("fisk") || l.contains("torsk") { return "🐟" }
    if l.contains("biff") || l.contains("steak")                  { return "🥩" }
    if l.contains("wok")                                           { return "🥘" }
    if l.contains("gryte")                                         { return "🫕" }
    if l.contains("pølse")                                         { return "🌭" }
    if l.contains("rest") || l.contains("leftover")               { return "♻️" }
    if l.contains("egg") || l.contains("omelett")                 { return "🍳" }
    if l.contains("curry")                                         { return "🍛" }
    if l.contains("sandwich") || l.contains("wrap")               { return "🥪" }
    return "🍽️"
}
