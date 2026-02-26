import SwiftUI
import Adhan
import UIKit

// MARK: - Muslim Pro Theme

private enum MuslimProTheme {
    static let accentGreen = Color(red: 0.18, green: 0.80, blue: 0.44)
}

// MARK: - Content View

struct ContentView: View {
    @State private var viewModel = AdhanHomeViewModel()
    @State private var calendarMode: CalendarMode = .gregorian
    @State private var showCalibrationInfo = false
    @AppStorage("prayed_prayers") private var prayedPrayersStorage: String = ""
    @State private var prayedPrayers: Set<Prayer> = []

    var body: some View {
        TabView {
            homeTab
                .tabItem { Label("Home", systemImage: "moon.stars.fill") }

            WorldClockView()
                .tabItem { Label("World", systemImage: "globe.asia.australia.fill") }

            qiblaTab
                .tabItem { Label("Qibla", systemImage: "location.north.fill") }

            calendarTab
                .tabItem { Label("Calendar", systemImage: "calendar") }

            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(MuslimProTheme.accentGreen)
        .task {
            viewModel.start()
            loadPrayedPrayers()
        }
        .onChange(of: prayedPrayers) { _, _ in
            savePrayedPrayers()
        }
    }

    // MARK: - Home Tab

    private var homeTab: some View {
        NavigationStack {
            ZStack {
                MuslimProBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        homeHeader
                        homeStatusRow
                        prayerList
                        markAllAsPrayedButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Home Header

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today, \(currentFullDateString)")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(viewModel.hijriDateText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                HStack(spacing: 20) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.top, 6)
            }

            HStack(spacing: 10) {
                InfoChip(icon: "location.fill", text: viewModel.locationLabel)
                InfoChip(icon: "slider.horizontal.3", text: viewModel.calculationMethod.displayName)
            }
        }
    }

    private var currentFullDateString: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: Date())
    }

    // MARK: - Home Status Row

    private var homeStatusRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                currentPrayerCard
                prayedProgressCard
            }

            HStack(spacing: 0) {
                Text("Imsak \(viewModel.imsakTimeText)")
                Text("  |  ")
                    .foregroundStyle(.white.opacity(0.3))
                Text("Sunrise \(viewModel.sunriseTimeText)")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
    }

    // MARK: - Now Card

    private var currentPrayerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Now")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())

            HStack(spacing: 6) {
                Text(viewModel.currentPrayerName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(currentPrayerEmoji)
                    .font(.system(size: 16))
            }

            Text(viewModel.currentPrayerTimeText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("\(viewModel.nextPrayerName) in \(viewModel.countdownText(from: context.date))")
                    .font(.caption)
                    .foregroundStyle(MuslimProTheme.accentGreen)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuslimProCard())
    }

    private var currentPrayerEmoji: String {
        viewModel.prayerRows.first(where: { $0.isCurrent })?.emoji ?? "☀️"
    }

    // MARK: - Progress Card

    private var prayedCount: Int { prayedPrayers.count }
    private var totalPrayers: Int { 5 }

    private var prayedProgressCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 4)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: CGFloat(prayedCount) / CGFloat(max(totalPrayers, 1)))
                    .stroke(MuslimProTheme.accentGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MuslimProTheme.accentGreen)
            }

            Text("\(prayedCount)/\(totalPrayers)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("prayed")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(MuslimProCard())
    }

    // MARK: - Prayer List

    private var prayerList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.prayerRows.filter { $0.prayer != .sunrise }) { row in
                PrayerRowCard(
                    row: row,
                    isPrayed: row.isNotificationEligible
                        ? Binding(
                            get: { prayedPrayers.contains(row.prayer) },
                            set: { isOn in
                                if isOn { prayedPrayers.insert(row.prayer) }
                                else { prayedPrayers.remove(row.prayer) }
                            }
                        )
                        : nil,
                    isMuted: row.isNotificationEligible
                        ? Binding(
                            get: { viewModel.isAdhanMuted(for: row.prayer) },
                            set: { viewModel.setAdhanMuted(for: row.prayer, isOn: $0) }
                        )
                        : nil,
                    nextPrayerDate: row.isNext ? viewModel.nextPrayerDate : nil
                )
            }
        }
    }

    // MARK: - Mark All Button

    private var markAllAsPrayedButton: some View {
        Button {
            prayedPrayers = [.fajr, .dhuhr, .asr, .maghrib, .isha]
        } label: {
            Text("Mark all as prayed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(MuslimProTheme.accentGreen)
                .clipShape(Capsule())
        }
    }

    // MARK: - Qibla Tab

    private var qiblaTab: some View {
        NavigationStack {
            ZStack {
                CompassBackground()
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Text("Target Heading")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(viewModel.qiblaHeadingDegrees)
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(viewModel.qiblaHeadingCardinal)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        Text("Current \(viewModel.currentHeadingText)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 16)

                    Spacer()

                    QiblaCompassView(
                        headingDegrees: viewModel.currentHeadingDegrees,
                        targetDegrees: viewModel.qiblaBearingDegrees,
                        isAligned: viewModel.isQiblaAligned
                    )
                    .onChange(of: viewModel.qiblaAngle) { _, newValue in
                        guard !viewModel.isHeadingCalibrationNeeded else { return }
                        let distance = min(newValue, 360 - newValue)
                        if distance <= 3 {
                            Haptics.shared.alignment()
                        }
                    }

                    Spacer()

                    VStack(spacing: 6) {
                        Text(viewModel.coordinateText)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(viewModel.locationLabel)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(viewModel.elevationText)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if viewModel.isHeadingCalibrationNeeded {
                        Button {
                            showCalibrationInfo = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Calibrate your compass for accuracy")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                Spacer(minLength: 0)
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 12)
                }
            }
            .navigationTitle("Qibla")
            .sheet(isPresented: $showCalibrationInfo) {
                CalibrationInfoSheet()
            }
        }
    }

    // MARK: - Calendar Tab

    private var calendarTab: some View {
        NavigationStack {
            ZStack {
                MuslimProBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        GlassHeader {
                            HStack {
                                Text("Calendar")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Picker("Mode", selection: $calendarMode) {
                                    ForEach(CalendarMode.allCases, id: \.self) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                        }

                        CalendarSummaryCard(
                            primaryTitle: calendarMode == .gregorian ? "Today" : "Hijri",
                            primaryValue: calendarMode == .gregorian
                                ? AdhanHomeViewModel.dateFormatter.string(from: Date())
                                : viewModel.hijriDateText,
                            secondaryTitle: calendarMode == .gregorian ? "Hijri" : "Today",
                            secondaryValue: calendarMode == .gregorian
                                ? viewModel.hijriDateText
                                : AdhanHomeViewModel.dateFormatter.string(from: Date()),
                            location: viewModel.locationLabel
                        )

                        MonthGridCard(mode: calendarMode)

                        PrayerScheduleCard(rows: viewModel.prayerRows)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Calendar")
        }
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        @Bindable var viewModel = viewModel

        return NavigationStack {
            ZStack {
                MuslimProBackground()
                    .ignoresSafeArea()
                List {
                Section("Prayer Calculation") {
                    Picker("Method", selection: $viewModel.calculationMethod) {
                        ForEach(AppCalculationMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }

                    Picker("Madhab", selection: $viewModel.madhab) {
                        ForEach(viewModel.madhabOptions, id: \.self) { madhab in
                            Text(viewModel.madhabName(madhab)).tag(madhab)
                        }
                    }
                }

                Section("Developer Info") {
                    Text("Built with ❤️ by Anas Khalid")
                        .font(.footnote)
                    Text("For feedback: anaskhan.ssif@gmail.com")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Prayer Row Card

private struct PrayerRowCard: View {
    let row: PrayerRow
    let isPrayed: Binding<Bool>?
    let isMuted: Binding<Bool>?
    let nextPrayerDate: Date?

    var body: some View {
        HStack(spacing: 12) {
            if let isPrayed {
                Button {
                    isPrayed.wrappedValue.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                            .background(
                                Circle()
                                    .fill(isPrayed.wrappedValue ? MuslimProTheme.accentGreen : Color.clear)
                            )
                            .frame(width: 24, height: 24)

                        if isPrayed.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            Text(row.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text(row.emoji)
                .font(.system(size: 14))

            if row.isCurrent {
                Text("Now")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MuslimProTheme.accentGreen)
                    .clipShape(Capsule())
            } else if row.isNext, let nextDate = nextPrayerDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let interval = max(nextDate.timeIntervalSince(context.date), 0)
                    Text("in \(Self.friendlyCountdown(interval))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer()

            Text(row.timeText)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            if let isMuted {
                Button {
                    isMuted.wrappedValue.toggle()
                } label: {
                    Image(systemName: isMuted.wrappedValue ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isMuted.wrappedValue ? .red.opacity(0.7) : .white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(row.isCurrent ? Color.white.opacity(0.10) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(row.isCurrent ? 0.15 : 0.06), lineWidth: 1)
        )
    }

    static func friendlyCountdown(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m \(s)s"
    }
}

// MARK: - Qibla Compass Components

private struct QiblaCompassView: View {
    let headingDegrees: Double
    let targetDegrees: Double
    let isAligned: Bool
    private let size: CGFloat = 230

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                .frame(width: size, height: size)

            ZStack {
                MinimalTicks()
                MinimalCardinals(size: size)

                QiblaTargetMarker()
                    .rotationEffect(.degrees(targetDegrees))
                    .opacity(isAligned ? 1 : 0.85)
            }
            .rotationEffect(.degrees(-headingDegrees))
            .animation(.easeInOut(duration: 0.12), value: headingDegrees)

            QiblaNeedle()

            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 8, height: 8)
        }
        .frame(width: size, height: size)
    }
}

private struct QiblaNeedle: View {
    var body: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 2, height: 96)
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
            .offset(y: -18)
    }
}

private struct QiblaTargetMarker: View {
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .offset(y: -96)
    }
}

private struct MinimalTicks: View {
    var body: some View {
        ForEach(0..<12, id: \.self) { index in
            let angle = Double(index) * 30
            Rectangle()
                .fill(Color.white.opacity(index % 3 == 0 ? 0.5 : 0.25))
                .frame(width: 1, height: index % 3 == 0 ? 10 : 6)
                .offset(y: -100)
                .rotationEffect(.degrees(angle))
        }
    }
}

private struct MinimalCardinals: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Text("N")
                .offset(y: -(size / 2) + 20)
            Text("E")
                .offset(x: size / 2 - 20)
            Text("S")
                .offset(y: size / 2 - 20)
            Text("W")
                .offset(x: -(size / 2 - 20))
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.7))
    }
}

private struct CalibrationInfoSheet: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("Calibrate Your Compass")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Move your phone in a figure‑8 pattern for a few seconds to improve compass accuracy.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CompassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.white.opacity(0.08), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
        }
    }
}

private enum Haptics {
    static let shared = HapticsController()
}

private final class HapticsController {
    private var lastFireDate = Date.distantPast

    func alignment() {
        let now = Date()
        if now.timeIntervalSince(lastFireDate) < 1.0 { return }
        lastFireDate = now
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }
}

// MARK: - Chips

private struct InfoChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.10))
        .clipShape(Capsule())
    }
}

// MARK: - Prayed Prayers Storage

private extension ContentView {
    func loadPrayedPrayers() {
        let tokens = prayedPrayersStorage.split(separator: ",").map(String.init)
        prayedPrayers = Set(tokens.compactMap(prayerFromKey))
    }

    func savePrayedPrayers() {
        let tokens = prayedPrayers.map(prayerKey).sorted()
        prayedPrayersStorage = tokens.joined(separator: ",")
    }

    func prayerKey(_ prayer: Prayer) -> String {
        switch prayer {
        case .fajr:
            return "fajr"
        case .dhuhr:
            return "dhuhr"
        case .asr:
            return "asr"
        case .maghrib:
            return "maghrib"
        case .isha:
            return "isha"
        default:
            return ""
        }
    }

    func prayerFromKey(_ key: String) -> Prayer? {
        switch key {
        case "fajr":
            return .fajr
        case "dhuhr":
            return .dhuhr
        case "asr":
            return .asr
        case "maghrib":
            return .maghrib
        case "isha":
            return .isha
        default:
            return nil
        }
    }
}

// MARK: - Calendar Components

private enum CalendarMode: CaseIterable {
    case gregorian
    case hijri

    var title: String {
        switch self {
        case .gregorian:
            return "Gregorian"
        case .hijri:
            return "Hijri"
        }
    }
}

private struct CalendarSummaryCard: View {
    let primaryTitle: String
    let primaryValue: String
    let secondaryTitle: String
    let secondaryValue: String
    let location: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(primaryTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text(primaryValue)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(secondaryTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text(secondaryValue)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeatherCard())
    }
}

private struct PrayerScheduleCard: View {
    let rows: [PrayerRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Prayer Schedule")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(row.timeText)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        if row.isNext {
                            Text("Next")
                                .font(.caption)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(MuslimProTheme.accentGreen)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 6)
                    if row.id != rows.last?.id {
                        Divider().background(Color.white.opacity(0.1))
                    }
                }
            }
        }
        .padding(18)
        .background(WeatherCard())
    }
}

private struct MonthGridCard: View {
    let mode: CalendarMode

    private var calendar: Calendar {
        switch mode {
        case .gregorian:
            return Calendar(identifier: .gregorian)
        case .hijri:
            return Calendar(identifier: .islamicUmmAlQura)
        }
    }

    private var headerText: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: Date())
    }

    private var days: [Date] {
        let today = Date()
        let range = calendar.range(of: .day, in: .month, for: today) ?? 1..<2
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        return range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        }
    }

    private var weekdayOffset: Int {
        let today = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let weekday = calendar.component(.weekday, from: start)
        return (weekday + 5) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(headerText)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }

                ForEach(0..<weekdayOffset, id: \.self) { _ in
                    Text("")
                        .frame(height: 32)
                }

                ForEach(days, id: \.self) { date in
                    let gregorianDay = Calendar(identifier: .gregorian).component(.day, from: date)
                    let hijriDay = Calendar(identifier: .islamicUmmAlQura).component(.day, from: date)

                    VStack(spacing: 4) {
                        Text("\(mode == .gregorian ? gregorianDay : hijriDay)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(mode == .gregorian ? hijriDay : gregorianDay)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(Calendar.current.isDateInToday(date) ? 0.18 : 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(18)
        .background(WeatherCard())
    }
}

// MARK: - Backgrounds & Cards

private struct MuslimProBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.12, blue: 0.17),
                Color(red: 0.05, green: 0.17, blue: 0.23),
                Color(red: 0.04, green: 0.12, blue: 0.17)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct MuslimProCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct WeatherCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}

private struct GlassHeader<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 20)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
