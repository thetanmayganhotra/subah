import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: AlarmSettings { didSet { settings.save(); settingsDidChange(old: oldValue) } }
    @Published var pick: SongPick?
    @Published var sky: SkyReport?
    @Published var weather: WeatherSnapshot?
    @Published var weatherNow: WeatherSnapshot?
    @Published var preparing = false
    @Published var note = ""
    @Published var nextFire: Date?
    @Published var ringing = false
    @Published var ringPick: SongPick?
    @Published var ringPhase = ""
    @Published var ringStart = Date()
    @Published var wakeStatus = ""
    @Published var wakeDirty = false
    @Published var launchAtLogin = false

    let player = PlayerService()
    private let volume = VolumeRamp()
    private let ringWindow = RingWindowController()

    private var history: [HistoryItem]
    private var lastFired: Date? = UserDefaults.standard.object(forKey: "lastFired") as? Date
    private var armedAt = Date.distantPast
    private var snoozeAt: Date?
    private var activeFire: Date?
    private var ringTesting = false
    private var ringTask: Task<Void, Never>?
    private var prepTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private var napGuard: NSObjectProtocol?      // keeps timers honest (no App Nap)
    private var preAlarm: NSObjectProtocol?      // keeps the Mac awake just before the alarm
    private var timer: Timer?
    private var slowTick = 0
    private var rerollSeen = Set<String>()

    init() {
        settings = AlarmSettings.load()
        history = Store.loadHistory()
        pick = Store.loadPick()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func start() {
        autoLocate()
        napGuard = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Subah alarm clock")
        recomputeNext()
        refreshSky()
        refreshWakeStatus()
        schedulePrepare(force: false, delay: 0.5)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
                try? await Task.sleep(nanoseconds: 8_000_000_000) // let the network come back
                self?.autoLocate()
                self?.schedulePrepare(force: false, delay: 3)
            }
        }
    }

    // MARK: - Location

    /// Follows the Mac's current location (roughly city-level) so weather is for where you actually wake up.
    func autoLocate() {
        guard settings.autoLocate else { return }
        Task {
            guard let p = await LocationService.detect(), settings.autoLocate else { return }
            let cur = settings.city
            if !cur.resolved || abs(cur.lat - p.lat) > 0.2 || abs(cur.lon - p.lon) > 0.2 { settings.city = p }
        }
    }

    // MARK: - Scheduling

    private func settingsDidChange(old: AlarmSettings) {
        let timing = old.hour != settings.hour || old.minute != settings.minute || old.weekdays != settings.weekdays
        let armed = old.enabled != settings.enabled
        if timing || armed { armedAt = Date() }
        recomputeNext()
        refreshSky()
        if timing || armed || old.wakeMac != settings.wakeMac { wakeDirty = true }
        if !old.autoLocate && settings.autoLocate { autoLocate() }

        let dayChanged = old.weekdays != settings.weekdays
        let pickAffecting = dayChanged || old.userName != settings.userName
            || old.birthLocal != settings.birthLocal || old.hasBirth != settings.hasBirth
            || old.birthPlace != settings.birthPlace || old.city != settings.city
        if pickAffecting { schedulePrepare(force: true, delay: 2) }
    }

    static func nextFire(after: Date, hour: Int, minute: Int, weekdays: Set<Int>) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let cal = Calendar.current
        for d in 0...8 {
            guard let day = cal.date(byAdding: .day, value: d, to: after) else { continue }
            var c = cal.dateComponents([.year, .month, .day], from: day)
            c.hour = hour; c.minute = minute; c.second = 0
            if let date = cal.date(from: c), date > after, weekdays.contains(cal.component(.weekday, from: date)) { return date }
        }
        return nil
    }

    func recomputeNext() {
        let after = max(lastFired ?? .distantPast, armedAt, Date().addingTimeInterval(-45 * 60))
        nextFire = Self.nextFire(after: after, hour: settings.hour, minute: settings.minute, weekdays: settings.weekdays)
    }

    private func tick() {
        let now = Date()
        slowTick += 1
        if slowTick % 600 == 0 { schedulePrepare(force: false, delay: 0.1) }
        if slowTick % 900 == 0 { refreshWeatherNow() }
        if let f = nextFire, settings.enabled, f.timeIntervalSince(now) < 240, f.timeIntervalSince(now) > -60 {
            if preAlarm == nil { preAlarm = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Alarm about to ring") }
        } else if let a = preAlarm, !ringing {
            ProcessInfo.processInfo.endActivity(a); preAlarm = nil
        }
        if ringing { return }
        if let s = snoozeAt, now >= s { snoozeAt = nil; ring(testing: false); return }
        guard let fire = nextFire, now >= fire else { return }
        lastFired = fire
        UserDefaults.standard.set(fire, forKey: "lastFired")
        recomputeNext()
        refreshSky()
        if settings.enabled && now.timeIntervalSince(fire) < 45 * 60 {
            activeFire = fire
            ring(testing: false)
        } else {
            schedulePrepare(force: false, delay: 1)
        }
    }

    // MARK: - Sky / weather / pick

    func makeSky(at date: Date) -> SkyReport {
        let tz = settings.city.resolved ? settings.city.timeZone : .current
        var birth: (instant: Date, place: Place)?
        if let bi = settings.birthInstant { birth = (bi, settings.birthPlace) }
        return Astro.report(birth: birth, at: date, tz: tz)
    }

    func refreshWeatherNow() {
        guard settings.city.resolved else { weatherNow = nil; return }
        let city = settings.city
        Task {
            let w = try? await WeatherService.forecast(city, at: Date())
            if city == self.settings.city { self.weatherNow = w }
        }
    }

    func refreshSky() {
        sky = makeSky(at: nextFire ?? Date())
        refreshWeatherNow()
        guard settings.city.resolved else { weather = nil; return }
        let city = settings.city
        let when = nextFire ?? Date()
        Task {
            let w = try? await WeatherService.forecast(city, at: when)
            if city == self.settings.city { self.weather = w }
        }
    }

    func schedulePrepare(force: Bool, delay: TimeInterval = 1) {
        prepTask?.cancel()
        prepTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.prepareDraft(force: force)
        }
    }

    private func prepareDraft(force: Bool) async {
        guard let fire = nextFire, !preparing, !ringing else { return }
        let stale = pick == nil || !Calendar.current.isDate(pick!.forDate, inSameDayAs: fire)
        let needsRefine = !stale && pick?.refined == false && fire.timeIntervalSinceNow < 10 * 3600
        guard force || stale || needsRefine else { return }
        preparing = true
        defer { preparing = false }
        rerollSeen = []
        let new = await buildPick(for: fire, refined: fire.timeIntervalSinceNow < 10 * 3600, avoid: [])
        pick = new
        Store.save(pick: new)
    }

    /// "Another one" button: next best song for the same sky, never one already shown for this morning.
    func reroll() {
        guard let fire = nextFire, !preparing else { return }
        if let cur = pick { rerollSeen.insert((cur.title + "|" + cur.artist).lowercased()) }
        prepTask?.cancel()
        Task {
            preparing = true
            defer { preparing = false }
            let new = await buildPick(for: fire, refined: fire.timeIntervalSinceNow < 10 * 3600, avoid: rerollSeen, salt: rerollSeen.count)
            pick = new
            Store.save(pick: new)
        }
    }

    /// Picks from the playlist using that morning's sky and weather. No AI, no network needed for the choice itself.
    func buildPick(for fire: Date, refined: Bool, avoid: Set<String>, salt: Int = 0) async -> SongPick {
        let sky = makeSky(at: fire)
        var wx: WeatherSnapshot?
        if settings.city.resolved { wx = try? await WeatherService.forecast(settings.city, at: fire) }
        return await makePick(for: fire, sky: sky, wx: wx, refined: refined, avoid: avoid, salt: salt)
    }

    private func makePick(for fire: Date, sky: SkyReport, wx: WeatherSnapshot?, refined: Bool, avoid: Set<String>, salt: Int) async -> SongPick {
        let s = Chooser.choose(sky: sky, weather: wx, history: history, fire: fire, exclude: avoid, salt: salt)
        var p = SongPick(title: s.title, artist: s.artist,
                         why: Chooser.reason(for: s, sky: sky, weather: wx, fire: fire),
                         greeting: Chooser.greeting(name: settings.userName, sky: sky, fire: fire),
                         mood: s.tags.filter { !["desi", "classic", "indie", "jazz", "film", "instrumental", "sacred", "rain", "sun", "cold"].contains($0) }
                             .sorted().prefix(2).joined(separator: ", "),
                         source: "playlist", forDate: fire, refined: refined)
        p.durationMs = s.durationMs > 0 ? s.durationMs : nil
        if let r = await ITunes.resolve(title: s.title, artist: s.artist) {
            p.artworkURL = r.artwork; p.previewURL = r.preview; p.storeURL = r.store
            if let ms = r.durationMs { p.durationMs = ms }
        }
        return p
    }

    // MARK: - Ringing

    func ring(testing: Bool) {
        guard !ringing else { return }
        ringing = true
        ringTesting = testing
        ringPick = nil
        ringStart = Date()
        ringPhase = testing ? "Reading the sky…" : ""
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Subah alarm")
        if let p = Process.launch("/usr/bin/caffeinate", ["-u", "-t", "8"]) { _ = p }
        ringWindow.show(self)

        ringTask = Task {
            var chosen: SongPick
            if testing {
                chosen = await buildPick(for: Date(), refined: true, avoid: [])
            } else if let cur = pick {
                chosen = cur
            } else {
                let fire = activeFire ?? Date()
                chosen = await makePick(for: fire, sky: makeSky(at: fire), wx: nil, refined: true, avoid: [], salt: 0)
            }
            guard !Task.isCancelled else { return }
            ringPick = chosen
            ringPhase = ""
            if !testing, history.last?.title != chosen.title || history.last.map({ Date().timeIntervalSince($0.date) > 3600 }) == true {
                history.append(HistoryItem(date: Date(), title: chosen.title, artist: chosen.artist))
                Store.save(history: history)
            }
            volume.fade(to: settings.fullVolume ? 100 : settings.volume, over: testing ? 12 : settings.fadeSeconds)
            await player.play(chosen)
        }
    }

    func snooze() {
        endRinging()
        snoozeAt = Date().addingTimeInterval(Double(settings.snoozeMinutes) * 60)
        note = "Snoozed until \(snoozeAt!.formatted(date: .omitted, time: .shortened))."
    }

    func stopAlarm() {
        endRinging()
        snoozeAt = nil
        if !ringTesting {
            activeFire = nil
            pick = nil
            Store.save(pick: nil)
            recomputeNext()
            refreshSky()
            schedulePrepare(force: true, delay: 1)
        }
    }

    private func endRinging() {
        ringTask?.cancel()
        player.stop()
        volume.cancel()
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        ringWindow.hide()
        ringing = false
    }

    var isSnoozing: Bool { snoozeAt != nil }

    // MARK: - Wake from sleep (pmset)

    func wakeCommand() -> String {
        guard settings.enabled, settings.wakeMac, !settings.weekdays.isEmpty else { return "pmset repeat cancel" }
        var total = settings.hour * 60 + settings.minute - 2 // wake 2 minutes early so the app is ready
        var days = settings.weekdays
        if total < 0 { total += 1440; days = Set(days.map { $0 == 1 ? 7 : $0 - 1 }) }
        let letters = [1: "U", 2: "M", 3: "T", 4: "W", 5: "R", 6: "F", 7: "S"]
        let d = days.sorted().compactMap { letters[$0] }.joined()
        return String(format: "pmset repeat wakeorpoweron %@ %02d:%02d:00", d, total / 60, total % 60)
    }

    func applyWakeSchedule() {
        let cmd = wakeCommand()
        wakeStatus = "Waiting for your password…"
        Task {
            let script = "do shell script \"/usr/bin/\(cmd)\" with administrator privileges"
            let (code, out) = await Process.run("/usr/bin/osascript", ["-e", script])
            if code == 0 {
                wakeDirty = false
                refreshWakeStatus()
            } else {
                wakeStatus = out.contains("-128") ? "Cancelled — your Mac won't wake itself yet." : "Couldn't set the wake schedule."
            }
        }
    }

    func refreshWakeStatus() {
        Task {
            let (_, out) = await Process.run("/usr/bin/pmset", ["-g", "sched"])
            let lines = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if let l = lines.first(where: { $0.contains("wake") && $0.contains("every") }) {
                wakeStatus = "Mac wakes: " + l.replacingOccurrences(of: "wakepoweron at ", with: "").replacingOccurrences(of: "wake at ", with: "")
            } else {
                wakeStatus = "No wake schedule set"
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            note = "Couldn't change login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

extension Process {
    @discardableResult
    static func launch(_ path: String, _ args: [String]) -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        return (try? p.run()) != nil ? p : nil
    }

    static func run(_ path: String, _ args: [String]) async -> (Int32, String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do { try p.run() } catch { cont.resume(returning: (-1, "\(error)")); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }
}
