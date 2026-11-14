import SwiftUI
import AppKit

@main
struct SubahApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Subah", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 540, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 560, height: 900)

        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            Image(systemName: "sun.horizon")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            Task { await SelfTest.run(); exit(0) }
            return
        }
        if CommandLine.arguments.contains("--seed") {
            Task { @MainActor in await SelfTest.seed(); exit(0) }
            return
        }
        if CommandLine.arguments.contains("--playtest") {
            Task { @MainActor in await SelfTest.playtest(); exit(0) }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[i + 1]
            Task { @MainActor in await SelfTest.snapshot(dir: dir); exit(0) }
            return
        }
        Task { @MainActor in AppModel.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// `Subah --selftest` prints the chart, weather and song pipeline so the plumbing can be checked without the UI.
enum SelfTest {
    /// Simulates a year and a half of mornings against the real sky maths, to prove songs don't repeat and the picks vary sensibly.
    static func run() async {
        var s = AlarmSettings.load()
        if !s.birthPlace.resolved {
            s.hasBirth = true
            s.birthPlace = (try? await WeatherService.geocode("Delhi")) ?? Place()
            s.birthLocal = Calendar.current.date(from: DateComponents(year: 2000, month: 9, day: 2, hour: 15, minute: 42))!
        }
        if !s.city.resolved { s.city = (try? await WeatherService.geocode("Delhi")) ?? Place() }
        let songs = Catalog.songs
        print("playlist size:", songs.count, "| artists:", Set(songs.map { $0.artist }).count)
        let birth = s.birthInstant.map { (instant: $0, place: s.birthPlace) }
        let start = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!.addingTimeInterval(6.5 * 3600)

        var hist: [HistoryItem] = []
        var seen: [String: Int] = [:]
        var firstRepeat: Int?
        var streak = 0, worstStreak = 0
        var lastArtist = ""
        let days = Int(ProcessInfo.processInfo.environment["SUBAH_DAYS"] ?? "") ?? 540
        for i in 0..<days {
            let fire = start.addingTimeInterval(Double(i) * 86400)
            let sky = Astro.report(birth: birth, at: fire, tz: s.city.timeZone)
            let r = Chooser.fnv("wx\(i)")
            let codes = [0, 0, 1, 2, 3, 3, 45, 61, 80, 95]
            let temp = 8 + Double(r % 31)
            let wx = WeatherSnapshot(temp: temp, feelsLike: temp, precipProb: codes[Int(r / 7 % 10)] >= 61 ? 70 : 10, code: codes[Int(r / 7 % 10)],
                                     cloud: 40, wind: 8, isDay: true, sunrise: "6:10 AM", sunset: "6:30 PM", placeName: s.city.name.components(separatedBy: ",").first ?? "Delhi", at: fire)
            let song = Chooser.choose(sky: sky, weather: wx, history: hist, fire: fire, exclude: [], salt: 0)
            if seen[song.key] != nil, firstRepeat == nil { firstRepeat = i }
            seen[song.key, default: 0] += 1
            streak = song.artist == lastArtist ? streak + 1 : 1
            worstStreak = max(worstStreak, streak)
            lastArtist = song.artist
            hist.append(HistoryItem(date: fire, title: song.title, artist: song.artist))
            if i < 14 {
                print(String(format: "%2d  %@ | %@ %@ | %.0f° code %d | %@ — %@ [%@]", i + 1,
                             fire.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), sky.nakshatra, sky.tithiName, temp, wx.code,
                             song.title, song.artist, song.tags.sorted().joined(separator: " ")))
            }
            if i == 0 { print("      why:", Chooser.reason(for: song, sky: sky, weather: wx, fire: fire)); print("      greeting:", Chooser.greeting(name: "Tanmay", sky: sky, fire: fire)) }
        }
        print("\nsimulated \(days) mornings: \(seen.count) distinct songs, first repeat on day \(firstRepeat.map(String.init) ?? "never"), longest same-artist streak \(worstStreak)")
        let top = seen.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) x\($0.value)" }
        print("most played:", top.joined(separator: "; "))
        var byTag: [String: Int] = [:]
        for k in seen.keys { if let sg = songs.first(where: { $0.key == k }) { for t in sg.tags { byTag[t, default: 0] += 1 } } }
        print("tag mix:", byTag.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    }
}

extension SelfTest {
    /// Renders the real views to PNGs (no screen-recording permission needed).
    @MainActor
    static func snapshot(dir: String) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let m = AppModel.shared
        m.settings.enabled = true
        m.settings.userName = "Tanmay"
        m.settings.hasBirth = true
        m.settings.birthPlace = (try? await WeatherService.geocode("New Delhi")) ?? Place()
        m.settings.city = (try? await WeatherService.geocode("Pune")) ?? Place()
        m.recomputeNext()
        m.refreshSky()
        let r = await ITunes.resolve(title: "Morning Has Broken", artist: "Cat Stevens")
        var p = SongPick(title: "Morning Has Broken", artist: "Cat Stevens",
                         why: "The Moon is in Uttara Ashadha, a steady, quietly ambitious star, and Pune is overcast and mild. This one opens slowly and lifts like the light does.",
                         greeting: "Good morning, Tanmay. Take it slow.", mood: "gentle, hopeful", forDate: m.nextFire ?? Date(), refined: false)
        if let r { p.artworkURL = r.artwork; p.previewURL = r.preview }
        m.pick = p
        m.ringPick = p
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        func shot(_ view: some View, _ w: CGFloat, _ h: CGFloat, _ name: String) async {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: w, height: h)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.orderFront(nil)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
            win.orderOut(nil)
        }
        for (name, pal) in [("home-dawn", Palette.dawn), ("home-night", Palette.night)] {
            await shot(ZStack { SkyBackground(palette: pal); HomeView() }.environment(\.palette, pal).environmentObject(m)
                .preferredColorScheme(pal.dark ? .dark : .light).foregroundStyle(pal.ink), 560, 1000, name)
        }
        await shot(ZStack { SkyBackground(palette: .day); SkyCard(startNow: true, openSettings: {}).padding(24) }
            .environment(\.palette, .day).environmentObject(m).foregroundStyle(Palette.day.ink), 560, 380, "sky-now")
        await shot(RingView().environmentObject(m), 620, 860, "ring")
        await shot(SettingsView().environmentObject(m).environment(\.palette, .dawn), 540, 700, "settings")
    }
}

extension SelfTest {
    /// Loads a song into the real player (muted) and reports whether YouTube actually starts playing.
    @MainActor
    static func playtest() async {
        let player = PlayerService()
        player.muted = true
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = player.webView
        win.orderFront(nil)
        let r = await ITunes.resolve(title: "Morning Has Broken", artist: "Cat Stevens")
        let pick = SongPick(title: "Morning Has Broken", artist: "Cat Stevens", previewURL: r?.preview, durationMs: r?.durationMs)
        let t0 = Date()
        Task { @MainActor in await player.play(pick) }
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            print(String(format: "%.1fs  status=%@ video=%d", Date().timeIntervalSince(t0), player.status, player.showsVideo ? 1 : 0))
            if player.showsVideo { break }
        }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        let title = try? await player.webView.evaluateJavaScript("player && player.getVideoData ? player.getVideoData().title + ' | t=' + player.getCurrentTime().toFixed(1) + ' | state=' + player.getPlayerState() : 'no player'")
        print("player says:", title ?? "nil")
    }
}

extension SelfTest {
    /// Fills in the owner's profile (used once, from the build folder).
    @MainActor
    static func seed() async {
        var s = AlarmSettings.load()
        s.userName = "Tanmay"
        s.hasBirth = true
        s.birthLocal = Calendar.current.date(from: DateComponents(year: 2000, month: 9, day: 2, hour: 15, minute: 42))!
        if var p = try? await WeatherService.geocode("Delhi") { p.query = "Delhi"; s.birthPlace = p }
        s.autoLocate = true
        if let p = await LocationService.detect() { s.city = p }
        s.save()
        print("birth place:", s.birthPlace.name, s.birthPlace.tz, "| wake-up city:", s.city.name)
        if let bi = s.birthInstant {
            let r = Astro.report(birth: (bi, s.birthPlace), at: Date(), tz: s.city.timeZone)
            if let n = r.natal {
                print("Lagna:", Astro.signs[n.lagnaSign], "| Moon:", Astro.signs[n.moon.sign], Astro.nakshatras[n.moon.nakIndex], "pada", n.moon.pada,
                      "| Sun:", Astro.signs[Int(n.placements[0].lon / 30)], "| dasha now:", n.maha, "/", n.antar)
            }
        }
    }
}
