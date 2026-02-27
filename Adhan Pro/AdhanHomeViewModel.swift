import Foundation
import Adhan
import AVFoundation
import CoreLocation
import MapKit
import Observation
import UserNotifications

@MainActor
@Observable
final class AdhanHomeViewModel: NSObject, CLLocationManagerDelegate {
    var locationLabel: String = "Locating..."
    var prayerRows: [PrayerRow] = []
    var nextPrayerName: String = "--"
    var nextPrayerTimeText: String = "--"
    var nextPrayerDate: Date?
    var currentPrayerName: String = "--"
    var currentPrayerTimeText: String = "--"
    var currentPrayerEndText: String = "--"
    var imsakTimeText: String = "--"
    var sunriseTimeText: String = "--"
    var qiblaText: String = "--"
    var qiblaHeadingDegrees: String = "--"
    var qiblaHeadingCardinal: String = "--"
    var qiblaBearingDegrees: Double = 0
    var currentHeadingDegrees: Double = 0
    var qiblaAngle: Double = 0
    var headingAccuracy: Double = -1
    var coordinateText: String = "--"
    var elevationText: String = "--"
    var hijriDateText: String = "--"
    var locationTimeZone: TimeZone = .current
    var notificationsEnabled: Bool = false
    var isLocationDenied: Bool = false
    var lastPlayedPrayer: Prayer?
    var isAdhanMuted: Bool = UserDefaults.standard.bool(forKey: "adhan_muted") {
        didSet {
            UserDefaults.standard.set(isAdhanMuted, forKey: "adhan_muted")
        }
    }

    var prayerMuteToggles: [Prayer] {
        [.fajr, .dhuhr, .asr, .maghrib, .isha]
    }

    var calculationMethod: AppCalculationMethod = .muslimWorldLeague {
        didSet {
            recalculatePrayerTimes()
        }
    }

    var madhab: Madhab = .hanafi {
        didSet {
            recalculatePrayerTimes()
        }
    }

    let madhabOptions: [Madhab] = [.shafi, .hanafi]

    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var currentPrayerTimes: PrayerTimes?
    private var audioPlayer: AVAudioPlayer?
    private var prayerMonitorTask: Task<Void, Never>?
    private var lastPlayedAt: Date?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        updateHijriDateText()
    }

    func start() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }

        Task {
            await refreshNotificationStatus()
        }

        startPrayerMonitor()
    }

    func countdownText(from now: Date) -> String {
        guard let nextPrayerDate else { return "--" }
        let interval = max(nextPrayerDate.timeIntervalSince(now), 0)
        return Self.formatInterval(interval)
    }

    func currentPrayerTimeLeft(from now: Date) -> String {
        guard let nextPrayerDate else { return "--" }
        let interval = max(nextPrayerDate.timeIntervalSince(now), 0)
        return Self.formatInterval(interval)
    }

    func madhabName(_ madhab: Madhab) -> String {
        switch madhab {
        case .shafi:
            return "Shafi"
        case .hanafi:
            return "Hanafi"
        @unknown default:
            return "Other"
        }
    }

    func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationsEnabled = granted
            if granted {
                schedulePrayerNotifications()
            }
        } catch {
            notificationsEnabled = false
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }

    private func schedulePrayerNotifications() {
        guard notificationsEnabled, let prayerTimes = currentPrayerTimes else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let prayers: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
        for prayer in prayers {
            guard isNotificationEnabled(for: prayer) else { continue }
            let time = prayerTimes.time(for: prayer)
            let content = UNMutableNotificationContent()
            let timeText = Self.timeFormatter.string(from: time)
            let locationText = locationLabel == "Locating..." ? "Your location" : locationLabel
            content.title = "\(prayerName(prayer)) - \(timeText) (\(locationText)) \(prayerEmoji(prayer))"
            content.body = "Adhan is now for \(prayerName(prayer))."
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }
            if isAdhanMuted || isAdhanMuted(for: prayer) {
                content.sound = nil
            } else if let soundName = adhanSoundName(for: prayer) {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
            } else {
                content.sound = .default
            }

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = "adhan-\(prayerName(prayer).lowercased())"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request)
        }
    }

    private func recalculatePrayerTimes() {
        guard let location = lastLocation else { return }
        let coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        var params = calculationMethod.adhanMethod.params
        params.madhab = madhab

        let dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        currentPrayerTimes = PrayerTimes(coordinates: coordinates, date: dateComponents, calculationParameters: params)
        updatePrayerRows()
        updateNextPrayerText()
        updateImsakAndSunrise(prayerTimes: currentPrayerTimes)
        updateQiblaText(for: coordinates)
        if notificationsEnabled {
            schedulePrayerNotifications()
        }
    }

    private func updatePrayerRows() {
        guard let prayerTimes = currentPrayerTimes else { return }
        let prayers: [Prayer] = [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha]
        let nextPrayer = prayerTimes.nextPrayer()
        let currentPrayer = prayerTimes.currentPrayer()

        prayerRows = prayers.map { prayer in
            let time = prayerTimes.time(for: prayer)
            return PrayerRow(
                prayer: prayer,
                name: prayerName(prayer),
                emoji: prayerEmoji(prayer),
                timeText: Self.timeFormatter.string(from: time),
                isNext: prayer == nextPrayer,
                isCurrent: prayer == currentPrayer,
                isNotificationEligible: adhanSoundName(for: prayer) != nil
            )
        }
    }

    private func updateNextPrayerText() {
        guard let prayerTimes = currentPrayerTimes else { return }
        guard let nextPrayer = prayerTimes.nextPrayer() else {
            nextPrayerName = "--"
            nextPrayerTimeText = "--"
            nextPrayerDate = nil
            return
        }

        nextPrayerName = prayerName(nextPrayer)
        let nextTime = prayerTimes.time(for: nextPrayer)
        nextPrayerTimeText = Self.timeFormatter.string(from: nextTime)
        nextPrayerDate = nextTime
        updateCurrentPrayerText(prayerTimes: prayerTimes, nextTime: nextTime)
    }

    private func updateImsakAndSunrise(prayerTimes: PrayerTimes?) {
        guard let prayerTimes else { return }
        let fajrTime = prayerTimes.time(for: .fajr)
        let imsakTime = Calendar.current.date(byAdding: .minute, value: -10, to: fajrTime) ?? fajrTime
        imsakTimeText = Self.timeFormatter.string(from: imsakTime)
        sunriseTimeText = Self.timeFormatter.string(from: prayerTimes.time(for: .sunrise))
    }

    private func updateCurrentPrayerText(prayerTimes: PrayerTimes, nextTime: Date) {
        if let currentPrayer = prayerTimes.currentPrayer() {
            let currentTime = prayerTimes.time(for: currentPrayer)
            currentPrayerName = prayerName(currentPrayer)
            currentPrayerTimeText = Self.timeFormatter.string(from: currentTime)
            currentPrayerEndText = Self.timeFormatter.string(from: nextTime)
        } else {
            currentPrayerName = "--"
            currentPrayerTimeText = "--"
            currentPrayerEndText = "--"
        }
    }

    func playAdhan(for prayer: Prayer) {
        guard !isAdhanMuted,
              !isAdhanMuted(for: prayer),
              let soundName = adhanSoundName(for: prayer),
              let url = Bundle.main.url(forResource: soundName, withExtension: nil) else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            lastPlayedPrayer = prayer
            lastPlayedAt = Date()
        } catch {
            // If audio fails, keep UI responsive without crashing.
        }
    }

    private func startPrayerMonitor() {
        prayerMonitorTask?.cancel()
        prayerMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkAndPlayPrayerIfNeeded()
                try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            }
        }
    }

    private func checkAndPlayPrayerIfNeeded() {
        guard !isAdhanMuted, let prayerTimes = currentPrayerTimes else { return }
        let now = Date()
        let prayers: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

        if let nextPrayerDate, now >= nextPrayerDate {
            updateNextPrayerText()
            updatePrayerRows()
        }

        for prayer in prayers {
            guard isNotificationEnabled(for: prayer), !isAdhanMuted(for: prayer) else { continue }
            let time = prayerTimes.time(for: prayer)
            let delta = now.timeIntervalSince(time)
            if delta >= 0 && delta <= 3 {
                if lastPlayedPrayer == prayer,
                   let lastPlayedAt,
                   Calendar.current.isDate(lastPlayedAt, equalTo: time, toGranularity: .minute) {
                    continue
                }
                playAdhan(for: prayer)
                updateNextPrayerText()
                updatePrayerRows()
                return
            }
        }
    }

    private func updateQiblaText(for coordinates: Coordinates) {
        let qibla = Qibla(coordinates: coordinates)
        let degrees = qibla.direction
        let cardinal = Self.cardinalDirection(for: degrees)
        qiblaText = String(format: "%.0f° %@", degrees, cardinal)
        qiblaHeadingDegrees = String(format: "%.0f°", degrees)
        qiblaHeadingCardinal = cardinal
        qiblaBearingDegrees = degrees
    }

    private func updateQiblaAngle(heading: CLHeading) {
        headingAccuracy = heading.headingAccuracy
        guard let location = lastLocation else { return }
        let coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let qibla = Qibla(coordinates: coordinates)
        let qiblaBearing = qibla.direction
        let headingDegrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        var angle = qiblaBearing - headingDegrees
        if angle < 0 { angle += 360 }
        currentHeadingDegrees = headingDegrees
        qiblaBearingDegrees = qiblaBearing
        qiblaAngle = angle
    }

    var currentHeadingText: String {
        let cardinal = Self.cardinalDirection(for: currentHeadingDegrees)
        return String(format: "%.0f° %@", currentHeadingDegrees, cardinal)
    }

    private func updateHijriDateText() {
        var hijriCalendar = Calendar(identifier: .islamicUmmAlQura)
        hijriCalendar.timeZone = locationTimeZone
        hijriDateText = Self.hijriFormatterString(from: Date(), calendar: hijriCalendar)
    }

    private func updateCoordinateText(for location: CLLocation) {
        coordinateText = Self.formatDMS(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func updateElevationText(for location: CLLocation) {
        let feet = location.altitude * 3.28084
        elevationText = String(format: "%.0f ft Elevation", feet)
    }

    private func updateLocationLabel(for location: CLLocation) {
        #if os(iOS)
        Task {
            do {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    locationLabel = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
                    return
                }

                let mapItems = try await request.mapItems
                if let mapItem = mapItems.first {
                    if let itemTimeZone = mapItem.timeZone {
                        locationTimeZone = itemTimeZone
                        updateHijriDateText()
                    }

                    if let address = mapItem.addressRepresentations {
                        let city = address.cityWithContext(.automatic) ?? address.cityName
                        let region = address.regionName
                        let parts = [city, region].compactMap { $0 }
                        if !parts.isEmpty {
                            locationLabel = parts.joined(separator: ", ")
                            return
                        }
                    }
                }

                locationLabel = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
            } catch {
                locationLabel = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
            }
        }
        #else
        locationLabel = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
        #endif
    }

    private func prayerName(_ prayer: Prayer) -> String {
        switch prayer {
        case .fajr:
            return "Fajr"
        case .sunrise:
            return "Sunrise"
        case .dhuhr:
            return "Dhuhr"
        case .asr:
            return "Asr"
        case .maghrib:
            return "Maghrib"
        case .isha:
            return "Isha"
        @unknown default:
            return "--"
        }
    }

    func displayName(for prayer: Prayer) -> String {
        prayerName(prayer)
    }

    func adhanSoundName(for prayer: Prayer) -> String? {
        switch prayer {
        case .fajr:
            return "adhan_fajr.m4a"
        case .dhuhr:
            return "adhan_dhuhr.m4a"
        case .asr:
            return "adhan_asr.m4a"
        case .maghrib:
            return "adhan_maghrib.m4a"
        case .isha:
            return "adhan_isha.m4a"
        default:
            return nil
        }
    }

    func prayerEmoji(_ prayer: Prayer) -> String {
        switch prayer {
        case .fajr:
            return "🌙"
        case .dhuhr:
            return "☀️"
        case .asr:
            return "🌤️"
        case .maghrib:
            return "🌇"
        case .isha:
            return "🌃"
        default:
            return "🕌"
        }
    }

    func isNotificationEnabled(for prayer: Prayer) -> Bool {
        let key = "notify_\(prayerName(prayer).lowercased())"
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    func setNotificationEnabled(for prayer: Prayer, isOn: Bool) {
        let key = "notify_\(prayerName(prayer).lowercased())"
        UserDefaults.standard.set(isOn, forKey: key)
        schedulePrayerNotifications()
    }

    func isAdhanMuted(for prayer: Prayer) -> Bool {
        let key = "mute_\(prayerName(prayer).lowercased())"
        if UserDefaults.standard.object(forKey: key) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    func setAdhanMuted(for prayer: Prayer, isOn: Bool) {
        let key = "mute_\(prayerName(prayer).lowercased())"
        UserDefaults.standard.set(isOn, forKey: key)
        if notificationsEnabled {
            schedulePrayerNotifications()
        }
    }

    static func formatInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    static func hijriFormatterString(from date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM d"
        let year = calendar.component(.year, from: date)
        return "\(formatter.string(from: date)), \(year) AH"
    }

    static func cardinalDirection(for degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) % directions.count
        return directions[index]
    }

    static func formatDMS(latitude: Double, longitude: Double) -> String {
        let lat = dmsComponents(from: latitude)
        let lon = dmsComponents(from: longitude)
        let latDir = latitude >= 0 ? "N" : "S"
        let lonDir = longitude >= 0 ? "E" : "W"
        return "\(lat.deg)°\(lat.min)′\(lat.sec)″ \(latDir)  \(lon.deg)°\(lon.min)′\(lon.sec)″ \(lonDir)"
    }

    private static func dmsComponents(from value: Double) -> (deg: Int, min: Int, sec: Int) {
        let absValue = abs(value)
        let deg = Int(absValue)
        let minutesFull = (absValue - Double(deg)) * 60
        let min = Int(minutesFull)
        let sec = Int(round((minutesFull - Double(min)) * 60))
        return (deg, min, sec)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isLocationDenied = false
            manager.requestLocation()
        case .denied, .restricted:
            isLocationDenied = true
            locationLabel = "Location Disabled"
        case .notDetermined:
            isLocationDenied = false
        @unknown default:
            isLocationDenied = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        updateLocationLabel(for: location)
        updateCoordinateText(for: location)
        updateElevationText(for: location)
        updateHijriDateText()
        recalculatePrayerTimes()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationLabel = "Location Unavailable"
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        updateQiblaAngle(heading: newHeading)
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return true
    }

    var isHeadingCalibrationNeeded: Bool {
        headingAccuracy < 0 || headingAccuracy > 15
    }

    var isQiblaAligned: Bool {
        let distance = min(qiblaAngle, 360 - qiblaAngle)
        return distance <= 3
    }
}

struct PrayerRow: Identifiable {
    let id = UUID()
    let prayer: Prayer
    let name: String
    let emoji: String
    let timeText: String
    let isNext: Bool
    let isCurrent: Bool
    let isNotificationEligible: Bool
}

enum AppCalculationMethod: String, CaseIterable, Identifiable {
    case muslimWorldLeague
    case northAmerica
    case egyptian
    case karachi
    case ummAlQura
    case dubai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .muslimWorldLeague:
            return "Muslim World League"
        case .northAmerica:
            return "North America"
        case .egyptian:
            return "Egyptian"
        case .karachi:
            return "Karachi"
        case .ummAlQura:
            return "Umm Al-Qura"
        case .dubai:
            return "Dubai"
        }
    }

    var adhanMethod: CalculationMethod {
        switch self {
        case .muslimWorldLeague:
            return .muslimWorldLeague
        case .northAmerica:
            return .northAmerica
        case .egyptian:
            return .egyptian
        case .karachi:
            return .karachi
        case .ummAlQura:
            return .ummAlQura
        case .dubai:
            return .dubai
        }
    }
}
