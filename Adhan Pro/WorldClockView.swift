import Adhan
import Combine
import MapKit
import SwiftUI

struct WorldClockView: View {
    @State private var viewModel = WorldClockViewModel()
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            distance: 22_000_000,
            heading: 0,
            pitch: 0
        )
    )
    @State private var selectedCity: WorldCity?
    @State private var selectedPrayer: Prayer? = nil
    @State private var isPlaybackActive = false
    @State private var playbackSpeed: Double = 1.0
    @State private var playbackBaseDate = Date()
    @State private var playbackStartDate: Date? = nil
    @State private var dotStyles: [String: CityDotStyle] = [:]
    @State private var dotStylesDate = Date.distantPast
    @State private var simulatedClock = Date()
    @State private var cameraRedrawToken = 0
    @State private var lastCameraUpdate = Date.distantPast
    @State private var calloutDismissTask: Task<Void, Never>? = nil
    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss 'UTC'"
        formatter.timeZone = .gmt
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    GeometryReader { geo in
                        Map(
                            position: $cameraPosition,
                            bounds: mapBounds,
                            interactionModes: [.pan, .zoom]
                        )
                        .mapStyle(.standard(elevation: .flat))
                        .onMapCameraChange(frequency: .continuous) { _ in
                            let now = Date()
                            if now.timeIntervalSince(lastCameraUpdate) > (1.0 / 30.0) {
                                lastCameraUpdate = now
                                cameraRedrawToken = (cameraRedrawToken + 1) % 10_000
                            }
                        }
                        .overlay {
                            ZStack {
                                WorldDotsOverlay(
                                    proxy: proxy,
                                    size: geo.size,
                                    cities: viewModel.cities,
                                    dotStyles: dotStyles,
                                    referenceDate: simulatedClock,
                                    selectedCity: selectedCity,
                                    selectedEvent: selectedCity.flatMap { city in
                                        viewModel.nextPrayerEvent(for: city, reference: simulatedClock)
                                    },
                                    redrawToken: cameraRedrawToken
                                )

                                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                                    let now = simulatedNow(for: context.date)
                                    let sweepLongitude = sweepLongitude(for: now)

                                    RadarOverlayCanvas(
                                        proxy: proxy,
                                        sweepLongitude: sweepLongitude
                                    )
                                }
                            }
                        }
                        .overlay(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.35),
                                    Color.clear,
                                    Color.black.opacity(0.25)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)
                        )
                        .simultaneousGesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    if let match = nearestCity(at: value.location, proxy: proxy, cities: viewModel.cities) {
                                        selectCity(match.city)
                                    } else {
                                        clearSelection()
                                    }
                                }
                        )
                        .ignoresSafeArea()
                    }
                }

                GeometryReader { geo in
                    if geo.size.width > geo.size.height {
                        landscapeOverlay
                    } else {
                        portraitOverlay
                    }
                }
            }
            .navigationTitle("World Clock")
            .task {
                viewModel.load()
                refreshDotStyles(reference: Date())
            }
            .onChange(of: selectedPrayer) { _, _ in
                refreshDotStyles(reference: simulatedClock)
            }
            .onReceive(clockTimer) { date in
                let now = simulatedNow(for: date)
                simulatedClock = now
                refreshDotStyles(reference: now)
            }
        }
    }

    private var portraitOverlay: some View {
        VStack {
            prayerFilterBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
            Spacer()
            playbackControls
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            if let selectedCity, let nextEvent = viewModel.nextPrayerEvent(for: selectedCity, reference: simulatedNow(for: Date())) {
                SelectedCityCard(city: selectedCity, event: nextEvent)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            legendCard
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
    }

    private var landscapeOverlay: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                prayerFilterBar
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            Spacer()

            HStack(alignment: .center, spacing: 12) {
                playbackControls
                if let selectedCity, let nextEvent = viewModel.nextPrayerEvent(for: selectedCity, reference: simulatedNow(for: Date())) {
                    SelectedCityCard(city: selectedCity, event: nextEvent)
                }
                Spacer(minLength: 0)
                legendCard
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var prayerFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                PrayerFilterChip(title: "All", isSelected: selectedPrayer == nil) {
                    selectedPrayer = nil
                }
                PrayerFilterChip(title: "Fajr", isSelected: selectedPrayer == .fajr) {
                    selectedPrayer = .fajr
                }
                PrayerFilterChip(title: "Dhuhr", isSelected: selectedPrayer == .dhuhr) {
                    selectedPrayer = .dhuhr
                }
                PrayerFilterChip(title: "Asr", isSelected: selectedPrayer == .asr) {
                    selectedPrayer = .asr
                }
                PrayerFilterChip(title: "Maghrib", isSelected: selectedPrayer == .maghrib) {
                    selectedPrayer = .maghrib
                }
                PrayerFilterChip(title: "Isha", isSelected: selectedPrayer == .isha) {
                    selectedPrayer = .isha
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var legendCard: some View {
        HStack(spacing: 12) {
            LegendItem(color: colorForPrayer(.fajr), text: "Fajr")
            LegendItem(color: colorForPrayer(.dhuhr), text: "Dhuhr")
            LegendItem(color: colorForPrayer(.asr), text: "Asr")
            LegendItem(color: colorForPrayer(.maghrib), text: "Maghrib")
            LegendItem(color: colorForPrayer(.isha), text: "Isha")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func sweepLongitude(for date: Date) -> Double {
        let utc = Calendar.current.dateComponents(in: .gmt, from: date)
        let hours = Double(utc.hour ?? 0)
        let minutes = Double(utc.minute ?? 0)
        let seconds = Double(utc.second ?? 0)
        let totalSeconds = hours * 3600 + minutes * 60 + seconds
        let progress = totalSeconds / 86400.0
        return progress * 360.0 - 180.0
    }

    private var mapBounds: MapCameraBounds {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 360)
        )
        return MapCameraBounds(centerCoordinateBounds: region, minimumDistance: 8_000_000, maximumDistance: 28_000_000)
    }

    private func colorForPrayer(_ prayer: Prayer) -> Color {
        switch prayer {
        case .fajr:
            return Color(red: 0.41, green: 0.65, blue: 0.98)
        case .dhuhr:
            return Color(red: 0.93, green: 0.83, blue: 0.60)
        case .asr:
            return Color(red: 0.97, green: 0.62, blue: 0.32)
        case .maghrib:
            return Color(red: 0.96, green: 0.42, blue: 0.41)
        case .isha:
            return Color(red: 0.62, green: 0.50, blue: 0.92)
        default:
            return .white
        }
    }

    private func cityDotStyle(for city: WorldCity, reference: Date) -> CityDotStyle {
        guard let nextEvent = viewModel.nextPrayerEvent(for: city, reference: reference) else {
            return CityDotStyle(color: Color.white.opacity(0.15), size: 2.5)
        }

        let matchesFilter = selectedPrayer == nil || selectedPrayer == nextEvent.prayer
        let color = colorForPrayer(nextEvent.prayer)
        let opacity = matchesFilter ? 0.9 : 0.25
        let size: CGFloat = 7.0

        return CityDotStyle(color: color.opacity(opacity), size: size)
    }

    private func simulatedNow(for date: Date) -> Date {
        guard isPlaybackActive, let startDate = playbackStartDate else {
            return date
        }

        let elapsed = date.timeIntervalSince(startDate)
        let simulated = playbackBaseDate.addingTimeInterval(elapsed * playbackSpeed)
        return wrapToUtcDay(simulated)
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaybackActive ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Live Playback")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(utcTimeString(for: simulatedNow(for: Date())))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Menu {
                ForEach(playbackSpeedOptions, id: \.self) { speed in
                    Button {
                        updatePlaybackSpeed(speed)
                    } label: {
                        Text(speedLabel(speed))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(speedLabel(playbackSpeed))
                        .font(.caption)
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func togglePlayback() {
        if isPlaybackActive {
            playbackBaseDate = simulatedNow(for: Date())
            playbackStartDate = nil
            isPlaybackActive = false
        } else {
            let now = Date()
            playbackBaseDate = now
            playbackStartDate = now
            isPlaybackActive = true
        }
    }

    private func updatePlaybackSpeed(_ speed: Double) {
        playbackBaseDate = simulatedNow(for: Date())
        playbackStartDate = Date()
        playbackSpeed = speed
    }

    private var playbackSpeedOptions: [Double] {
        [0.5, 1, 2, 4, 8, 12, 24, 50, 100, 200, 400]
    }

    private func speedLabel(_ speed: Double) -> String {
        if speed == 1 {
            return "1x"
        }
        if speed == 0.5 {
            return "0.5x"
        }
        return "\(Int(speed))x"
    }

    private func utcTimeString(for date: Date) -> String {
        WorldClockView.utcFormatter.string(from: date)
    }

    private func wrapToUtcDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let startOfDay = calendar.startOfDay(for: date)
        let seconds = date.timeIntervalSince(startOfDay)
        let wrapped = seconds.truncatingRemainder(dividingBy: 86400)
        return startOfDay.addingTimeInterval(wrapped)
    }

    private var clockTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    }

    private func refreshDotStyles(reference: Date) {
        guard reference.timeIntervalSince(dotStylesDate) > 10 else {
            return
        }
        dotStylesDate = reference
        let styles = viewModel.cities.reduce(into: [String: CityDotStyle]()) { result, city in
            result[city.id] = cityDotStyle(for: city, reference: reference)
        }
        dotStyles = styles
    }

    private func cachedStyle(for city: WorldCity) -> CityDotStyle {
        dotStyles[city.id] ?? CityDotStyle(color: .white.opacity(0.12), size: 7)
    }

    private func selectCity(_ city: WorldCity) {
        selectedCity = city
        calloutDismissTask?.cancel()
        calloutDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if selectedCity?.id == city.id {
                selectedCity = nil
            }
        }
    }

    private func clearSelection() {
        selectedCity = nil
        calloutDismissTask?.cancel()
        calloutDismissTask = nil
    }

    private func nearestCity(at location: CGPoint, proxy: MapProxy, cities: [WorldCity]) -> (city: WorldCity, point: CGPoint)? {
        var closest: (WorldCity, CGPoint, CGFloat)? = nil
        for city in cities {
            guard let point = proxy.convert(
                CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
                to: .local
            ) else { continue }

            let dx = point.x - location.x
            let dy = point.y - location.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance > 16 { continue }
            if let current = closest, distance >= current.2 { continue }
            closest = (city, point, distance)
        }
        if let closest {
            return (closest.0, closest.1)
        }
        return nil
    }
}

private struct CityDotStyle {
    let color: Color
    let size: CGFloat
}

private struct RadarOverlayCanvas: View {
    let proxy: MapProxy
    let sweepLongitude: Double

    var body: some View {
        Canvas { context, size in
            context.blendMode = .plusLighter

            drawSweep(context: &context, size: size)
        }
        .allowsHitTesting(false)
    }

    private func drawSweep(context: inout GraphicsContext, size: CGSize) {
        guard let top = proxy.convert(CLLocationCoordinate2D(latitude: 80, longitude: sweepLongitude), to: .local),
              let bottom = proxy.convert(CLLocationCoordinate2D(latitude: -80, longitude: sweepLongitude), to: .local) else {
            return
        }

        var corePath = Path()
        corePath.move(to: top)
        corePath.addLine(to: bottom)
        context.stroke(corePath, with: .color(.white.opacity(0.7)), lineWidth: 1)
    }

}

private struct CityBaseDot: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .stroke(Color.black.opacity(0.35), lineWidth: 1)
            .background(Circle().fill(color))
            .frame(width: size, height: size)
    }
}

private struct WorldDotsOverlay: View {
    let proxy: MapProxy
    let size: CGSize
    let cities: [WorldCity]
    let dotStyles: [String: CityDotStyle]
    let referenceDate: Date
    let selectedCity: WorldCity?
    let selectedEvent: WorldPrayerEvent?
    let redrawToken: Int

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                _ = redrawToken
                for city in cities {
                    guard let point = proxy.convert(
                        CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
                        to: .local
                    ) else { continue }

                    if point.x < -10 || point.y < -10 || point.x > canvasSize.width + 10 || point.y > canvasSize.height + 10 {
                        continue
                    }

                    let style = dotStyles[city.id] ?? CityDotStyle(color: .white.opacity(0.12), size: 6)
                    let rect = CGRect(
                        x: point.x - style.size / 2,
                        y: point.y - style.size / 2,
                        width: style.size,
                        height: style.size
                    )

                    let path = Path(ellipseIn: rect)
                    context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 1)
                    context.fill(path, with: .color(style.color))
                }
            }
            .allowsHitTesting(false)

            if let selectedCity,
               let point = proxy.convert(
                   CLLocationCoordinate2D(latitude: selectedCity.latitude, longitude: selectedCity.longitude),
                   to: .local
               ) {
                CityCallout(city: selectedCity, event: selectedEvent)
                    .position(x: point.x, y: max(20, point.y - 18))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CityCallout: View {
    let city: WorldCity
    let event: WorldPrayerEvent?

    var body: some View {
        let display = event
        VStack(spacing: 2) {
            Text("\(city.name), \(city.country)")
                .font(.caption2)
                .foregroundStyle(.white)
            if let display {
                Text("\(display.prayerName) • \(display.timeText)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
    }
}

private struct PrayerFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.12))
                )
        }
    }
}

private struct SelectedCityCard: View {
    let city: WorldCity
    let event: WorldPrayerEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(city.name), \(city.country)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Next: \(event.prayerName) • \(event.timeText)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.8))
            Text(city.timeZone)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    WorldClockView()
        .preferredColorScheme(.dark)
}
