import Foundation
import Adhan
import Observation

@MainActor
@Observable
final class WorldClockViewModel {
    var cities: [WorldCity] = []
    var isLoading: Bool = true

    private let calculationMethod: CalculationMethod = .muslimWorldLeague
    private var prayerCache: [String: PrayerTimes] = [:]

    func load() {
        if !cities.isEmpty { return }
        isLoading = true

        Task {
            do {
                let loaded = try await loadCities()
                cities = loaded
            } catch {
                cities = []
            }
            isLoading = false
        }
    }

    func pins(reference: Date) -> [WorldClockPin] {
        cities.compactMap { city in
            guard let timeZone = TimeZone(identifier: city.timeZone) else { return nil }
            let status = adhanStatus(for: city, reference: reference, timeZone: timeZone)
            guard let nextEvent = nextPrayerEvent(for: city, reference: reference, timeZone: timeZone) else { return nil }
            return WorldClockPin(
                city: city,
                prayer: nextEvent.prayer,
                date: nextEvent.date,
                timeText: nextEvent.timeText,
                status: status
            )
        }
    }

    func prayerPulse(for city: WorldCity, reference: Date, windowSeconds: TimeInterval = 120, filter: Prayer? = nil) -> WorldPrayerPulse? {
        guard let timeZone = TimeZone(identifier: city.timeZone) else { return nil }
        let prayers: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
        guard let prayerTimes = prayerTimes(for: city, reference: reference, timeZone: timeZone) else { return nil }

        for prayer in prayers {
            if let filter, filter != prayer { continue }
            let time = prayerTimes.time(for: prayer)
            let delta = abs(time.timeIntervalSince(reference))
            if delta <= windowSeconds {
                return WorldPrayerPulse(prayer: prayer, date: time)
            }
        }
        return nil
    }

    private func adhanStatus(for city: WorldCity, reference: Date, timeZone: TimeZone) -> WorldAdhanStatus {
        let prayers: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
        guard let prayerTimes = prayerTimes(for: city, reference: reference, timeZone: timeZone) else { return .later }
        for prayer in prayers {
            let time = prayerTimes.time(for: prayer)
            let delta = abs(time.timeIntervalSince(reference))
            if delta <= 120 {
                return .now
            }
            if time > reference && time.timeIntervalSince(reference) <= 3600 {
                return .soon
            }
        }
        return .later
    }

    func nextPrayerEvent(for city: WorldCity, reference: Date) -> WorldPrayerEvent? {
        guard let timeZone = TimeZone(identifier: city.timeZone) else { return nil }
        return nextPrayerEvent(for: city, reference: reference, timeZone: timeZone)
    }

    private func nextPrayerEvent(for city: WorldCity, reference: Date, timeZone: TimeZone) -> WorldPrayerEvent? {
        let prayers: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
        let calendar = calendar(in: timeZone)

        let todayComponents = calendar.dateComponents([.year, .month, .day], from: reference)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: reference) ?? reference
        let tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)

        var allEvents: [WorldPrayerEvent] = []
        allEvents.append(contentsOf: events(for: city, prayers: prayers, calendar: calendar, dateComponents: todayComponents))
        allEvents.append(contentsOf: events(for: city, prayers: prayers, calendar: calendar, dateComponents: tomorrowComponents))

        return allEvents
            .filter { $0.date >= reference }
            .sorted { $0.date < $1.date }
            .first
    }

    private func prayerTimes(for city: WorldCity, reference: Date, timeZone: TimeZone) -> PrayerTimes? {
        let calendar = calendar(in: timeZone)
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: reference)
        let dateKey = dateKey(for: reference, timeZone: timeZone)
        let cacheKey = "\(city.id)-\(dateKey)"
        if let cached = prayerCache[cacheKey] {
            return cached
        }

        let coordinates = Coordinates(latitude: city.latitude, longitude: city.longitude)
        let params = calculationMethod.params
        guard let prayerTimes = PrayerTimes(coordinates: coordinates, date: dateComponents, calculationParameters: params) else {
            return nil
        }
        prayerCache[cacheKey] = prayerTimes
        return prayerTimes
    }

    private func events(for city: WorldCity, prayers: [Prayer], calendar: Calendar, dateComponents: DateComponents) -> [WorldPrayerEvent] {
        let coordinates = Coordinates(latitude: city.latitude, longitude: city.longitude)
        let params = calculationMethod.params
        guard let prayerTimes = PrayerTimes(coordinates: coordinates, date: dateComponents, calculationParameters: params) else {
            return []
        }

        return prayers.map { prayer in
            let time = prayerTimes.time(for: prayer)
            return WorldPrayerEvent(
                city: city,
                prayer: prayer,
                date: time,
                timeText: Self.timeFormatter.string(from: time, in: calendar)
            )
        }
    }

    private func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func dateKey(for reference: Date, timeZone: TimeZone) -> String {
        let formatter = Self.dateKeyFormatter
        formatter.timeZone = timeZone
        return formatter.string(from: reference)
    }

    private func loadCities() async throws -> [WorldCity] {
        guard let url = Bundle.main.url(forResource: "WorldCities", withExtension: "json") else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([WorldCity].self, from: data)
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .gmt
        return formatter
    }()
}

struct WorldCity: Codable, Identifiable {
    var id: String { "\(name)-\(countryCode)" }
    let name: String
    let countryCode: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
    let population: Int
}

struct WorldPrayerEvent: Identifiable {
    let id = UUID()
    let city: WorldCity
    let prayer: Prayer
    let date: Date
    let timeText: String

    var prayerName: String {
        switch prayer {
        case .fajr:
            return "Fajr"
        case .dhuhr:
            return "Dhuhr"
        case .asr:
            return "Asr"
        case .maghrib:
            return "Maghrib"
        case .isha:
            return "Isha"
        default:
            return "Prayer"
        }
    }
}

struct WorldClockPin: Identifiable {
    let id = UUID()
    let city: WorldCity
    let prayer: Prayer
    let date: Date
    let timeText: String
    let status: WorldAdhanStatus

    var coordinate: (latitude: Double, longitude: Double) {
        (city.latitude, city.longitude)
    }

    var prayerName: String {
        switch prayer {
        case .fajr:
            return "Fajr"
        case .dhuhr:
            return "Dhuhr"
        case .asr:
            return "Asr"
        case .maghrib:
            return "Maghrib"
        case .isha:
            return "Isha"
        default:
            return "Prayer"
        }
    }
}

enum WorldAdhanStatus {
    case now
    case soon
    case later
}

struct WorldPrayerPulse {
    let prayer: Prayer
    let date: Date
}

private extension DateFormatter {
    func string(from date: Date, in calendar: Calendar) -> String {
        let originalCalendar = self.calendar
        self.calendar = calendar
        let text = string(from: date)
        self.calendar = originalCalendar
        return text
    }
}
