import AppKit
import CoreLocation
import SwiftUI

// MARK: - Prayer Time Model

struct PrayerTime: Identifiable {
    var id: String { name }
    let name: String
    let date: Date

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Prayer Time Calculator

struct PrayerCalculator {
    enum Method {
        case kemenag  // Indonesia: Fajr 20°, Isha 18°
    }

    static func times(for date: Date, latitude: Double, longitude: Double, method: Method = .kemenag) -> [PrayerTime] {
        let cal = Calendar(identifier: .gregorian)
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.timeZone = TimeZone.current
        let tzOffset = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600.0

        guard let y = comps.year, let m = comps.month, let d = comps.day else { return [] }

        let jd = julianDay(year: y, month: m, day: d)
        let (decl, eqt) = sunPosition(jd: jd)

        let dhuhrUT = 12.0 - longitude / 15.0 - eqt
        let sunriseAngle = 0.8333 + 0.0347 * sqrt(altitude(for: latitude))
        let sunriseT = sunAngleHourAngle(latitude: latitude, declination: decl, angle: sunriseAngle)

        let fajrAngle: Double
        let ishaAngle: Double
        switch method {
        case .kemenag: fajrAngle = 20.0; ishaAngle = 18.0
        }

        let fajrOffset = sunAngleHourAngle(latitude: latitude, declination: decl, angle: fajrAngle)
        let ishaOffset = sunAngleHourAngle(latitude: latitude, declination: decl, angle: ishaAngle)
        let asrOffset = asrHourAngle(latitude: latitude, declination: decl, shadowFactor: 1)

        let fajrUT = dhuhrUT - fajrOffset
        let sunriseUT = dhuhrUT - sunriseT
        let asrUT = dhuhrUT + asrOffset
        let maghribUT = dhuhrUT + sunriseT
        let ishaUT = dhuhrUT + ishaOffset

        func toDate(_ ut: Double) -> Date {
            let local = ut + tzOffset
            var c = cal.dateComponents([.year, .month, .day], from: date)
            c.hour = Int(local)
            c.minute = Int((local - Double(Int(local))) * 60)
            c.second = 0
            return cal.date(from: c) ?? date
        }

        _ = sunriseUT

        return [
            PrayerTime(name: "Subuh",   date: toDate(fajrUT)),
            PrayerTime(name: "Dzuhur",  date: toDate(dhuhrUT)),
            PrayerTime(name: "Ashar",   date: toDate(asrUT)),
            PrayerTime(name: "Maghrib", date: toDate(maghribUT)),
            PrayerTime(name: "Isya",    date: toDate(ishaUT)),
        ]
    }

    // MARK: - Astronomy Helpers

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = Double(y / 100)
        let b = 2 - a + Double(Int(a / 4))
        return Double(Int(365.25 * Double(y + 4716))) +
               Double(Int(30.6001 * Double(m + 1))) +
               Double(day) + b - 1524.5
    }

    private static func sunPosition(jd: Double) -> (declination: Double, equationOfTime: Double) {
        let d = jd - 2451545.0
        let g = deg2rad((357.529 + 0.98560028 * d).truncatingRemainder(dividingBy: 360))
        let q = (280.459 + 0.98564736 * d).truncatingRemainder(dividingBy: 360)
        let l = deg2rad((q + 1.915 * sin(g) + 0.020 * sin(2 * g)).truncatingRemainder(dividingBy: 360))
        let e = deg2rad(23.439 - 0.00000036 * d)
        let ra = rad2deg(atan2(cos(e) * sin(l), cos(l)))
        let declination = asin(sin(e) * sin(l))
        let eqt = q / 15.0 - fixHour(ra / 15.0)
        return (declination, eqt)
    }

    private static func sunAngleHourAngle(latitude: Double, declination: Double, angle: Double) -> Double {
        let lat = deg2rad(latitude)
        let a = deg2rad(-angle) - sin(lat) * sin(declination)
        let b = cos(lat) * cos(declination)
        guard abs(a / b) <= 1 else { return 0 }
        return rad2deg(acos(a / b)) / 15.0
    }

    private static func asrHourAngle(latitude: Double, declination: Double, shadowFactor: Double) -> Double {
        let lat = deg2rad(latitude)
        let target = atan(1.0 / (shadowFactor + tan(abs(lat - declination))))
        let a = sin(target) - sin(lat) * sin(declination)
        let b = cos(lat) * cos(declination)
        guard abs(a / b) <= 1 else { return 0 }
        return rad2deg(acos(a / b)) / 15.0
    }

    private static func altitude(for latitude: Double) -> Double {
        max(0, latitude)
    }

    private static func fixHour(_ h: Double) -> Double {
        var h = h.truncatingRemainder(dividingBy: 24)
        if h < 0 { h += 24 }
        return h
    }

    private static func deg2rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func rad2deg(_ r: Double) -> Double { r * 180 / .pi }
}

// MARK: - Prayer Schedule Logic

enum PrayerSchedule {
    static func nextPrayer(after now: Date, in prayers: [PrayerTime]) -> PrayerTime? {
        prayers.first { $0.date > now }
    }

    static func menuBarTitle(next: PrayerTime?) -> String {
        guard let p = next else { return "🕌 Sholat" }
        return "🕌 \(p.name) \(p.timeString)"
    }
}

// MARK: - Location Manager

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var status: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            manager.requestLocation()
        default:
            break
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.location = loc }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s == .authorizedAlways || s == .authorized {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var prayers: [PrayerTime] = []
    @Published var now: Date = Date()

    private var timer: Timer?
    let locationManager = LocationManager()

    init() {
        loadPrayers()
        startTimer()

        // Reload prayers when location updates
        locationManager.$location
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.loadPrayers() }
            .store(in: &cancellables)

        locationManager.requestLocation()
    }

    private var cancellables = Set<AnyCancellable>()

    private func startTimer() {
        // Fire every 30 seconds to keep the menu bar label fresh
        let nextMinute = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(60)

        let initialDelay = nextMinute.timeIntervalSinceNow
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
            Task { @MainActor [weak self] in
                self?.tick()
                self?.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.tick() }
                }
            }
        }
    }

    private func tick() {
        now = Date()
        // Reload when day changes
        if !Calendar.current.isDateInToday(prayers.first?.date ?? Date()) {
            loadPrayers()
        }
    }

    func loadPrayers() {
        let date = Date()
        if let loc = locationManager.location {
            prayers = PrayerCalculator.times(
                for: date,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
        } else {
            // Jakarta fallback until location is available
            prayers = PrayerCalculator.times(for: date, latitude: -6.2088, longitude: 106.8456)
        }
        now = date
    }

    var nextPrayer: PrayerTime? {
        // After last prayer today, wrap to first prayer tomorrow
        if let next = PrayerSchedule.nextPrayer(after: now, in: prayers) {
            return next
        }
        // All today's prayers are done — compute tomorrow's Subuh
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        if let loc = locationManager.location {
            let tomorrowPrayers = PrayerCalculator.times(
                for: tomorrow,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
            return tomorrowPrayers.first
        }
        return prayers.first
    }
}

import Combine

// MARK: - App Entry Point

@main
struct SholatBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PrayerMenuView()
                .environmentObject(state)
        } label: {
            Text(PrayerSchedule.menuBarTitle(next: state.nextPrayer))
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Views

struct PrayerMenuView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Waktu Sholat")
                        .font(.headline)
                    Spacer()
                    if state.locationManager.location == nil {
                        Image(systemName: "location.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Menggunakan lokasi default (Jakarta)")
                    }
                }
                Text(dateHeader)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 14)

            // Prayer rows
            VStack(spacing: 0) {
                ForEach(state.prayers) { prayer in
                    PrayerMenuRow(
                        prayer: prayer,
                        isPast: prayer.date < state.now,
                        isNext: prayer.id == state.nextPrayer?.id
                    )
                }
            }
            .padding(.vertical, 6)

            Divider()
                .padding(.horizontal, 14)

            // Quit button
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 220)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private var dateHeader: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM yyyy"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: state.now)
    }
}

struct PrayerMenuRow: View {
    let prayer: PrayerTime
    let isPast: Bool
    let isNext: Bool

    private var textColor: Color {
        isPast ? Color(nsColor: .tertiaryLabelColor) : .primary
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(isNext ? 1 : 0)

            Text(prayer.name)
                .foregroundStyle(textColor)
                .fontWeight(isNext ? .semibold : .regular)
                .frame(width: 70, alignment: .leading)

            Spacer()

            Text(prayer.timeString)
                .foregroundStyle(textColor)
                .fontWeight(isNext ? .semibold : .regular)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(isNext ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}
