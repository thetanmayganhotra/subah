import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let pal = Palette.forDate(ctx.date)
            ZStack {
                SkyBackground(palette: pal)
                HomeView()
            }
            .environment(\.palette, pal)
            .preferredColorScheme(pal.dark ? .dark : .light)
            .foregroundStyle(pal.ink)
        }
        .background(WindowConfigurator())
    }
}

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var pal
    @State private var showSettings = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header
                AlarmCard()
                SongCard()
                SkyCard(openSettings: { showSettings = true })
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(model) }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("subah").font(.serif(34, .light)).italic()
                Text("a different song for every morning").font(.system(size: 12)).foregroundStyle(pal.sub)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15)).padding(10)
                    .background(Circle().fill(pal.ink.opacity(0.07)))
            }
            .buttonStyle(.plain)
        }
    }

    var footer: some View {
        VStack(spacing: 12) {
            PillButton(title: "Try it now", icon: "sunrise", filled: true) { model.ring(testing: true) }
            Text("Your Mac has to be on power and the app running (it sits in the menu bar). Lid open is safest.")
                .font(.system(size: 11)).foregroundStyle(pal.sub).multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
}

// MARK: - Alarm

struct AlarmCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var pal

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                TimelineView(.periodic(from: .now, by: 20)) { _ in
                    Text(statusLine).font(.system(size: 13)).foregroundStyle(pal.sub)
                }
                Spacer()
                Toggle("", isOn: $model.settings.enabled).toggleStyle(.switch).labelsHidden().tint(pal.accent)
            }
            TimeDial(hour: $model.settings.hour, minute: $model.settings.minute)
                .opacity(model.settings.enabled ? 1 : 0.45)
            DayChips(days: $model.settings.weekdays)
            HStack {
                PillButton(title: "Set to now + 2 min", icon: "clock") {
                    let t = Date().addingTimeInterval(120)
                    let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                    model.settings.hour = c.hour ?? 6
                    model.settings.minute = c.minute ?? 0
                    model.settings.enabled = true
                }
                Spacer()
            }
            Divider().overlay(pal.ink.opacity(0.08))
            wakeRow
        }
        .card()
    }

    var statusLine: String {
        guard model.settings.enabled, let f = model.nextFire else { return "Alarm is off" }
        let s = Int(f.timeIntervalSinceNow)
        if s <= 0 { return "Ringing about now" }
        let h = s / 3600, m = (s % 3600) / 60
        return "Rings in " + (h > 0 ? "\(h)h \(m)m" : "\(m)m")
    }

    var wakeRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "powersleep").font(.system(size: 14)).foregroundStyle(pal.sub)
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Wake my Mac from sleep", isOn: $model.settings.wakeMac).toggleStyle(.checkbox).font(.system(size: 13))
                Text(model.wakeStatus).font(.system(size: 11)).foregroundStyle(pal.sub)
            }
            Spacer()
            if model.wakeDirty {
                PillButton(title: "Update wake", icon: "lock") { model.applyWakeSchedule() }
            }
        }
    }
}

struct TimeDial: View {
    @Environment(\.palette) var pal
    @Binding var hour: Int
    @Binding var minute: Int

    var h12: Int { hour % 12 == 0 ? 12 : hour % 12 }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            column(String(h12), up: { hour = (hour + 1) % 24 }, down: { hour = (hour + 23) % 24 })
            Text(":").font(.serif(72, .ultraLight)).offset(y: -6)
            column(String(format: "%02d", minute), up: { minute = (minute + 1) % 60 }, down: { minute = (minute + 59) % 60 })
            Button { hour = (hour + 12) % 24 } label: {
                Text(hour < 12 ? "AM" : "PM").font(.serif(20, .medium)).foregroundStyle(pal.accent)
                    .padding(.leading, 10).padding(.top, 26)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    func column(_ text: String, up: @escaping () -> Void, down: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            arrow("chevron.up", up)
            Text(text).font(.serif(84, .ultraLight)).monospacedDigit().frame(minWidth: 96)
            arrow("chevron.down", down)
        }
    }

    func arrow(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12, weight: .semibold)).foregroundStyle(pal.sub).frame(width: 44, height: 22)
        }
        .buttonStyle(.plain)
    }
}

struct DayChips: View {
    @Environment(\.palette) var pal
    @Binding var days: Set<Int>
    let labels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<7, id: \.self) { i in
                let day = i + 1
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(labels[i]).font(.system(size: 13, weight: .medium))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(on ? (pal.dark ? Color(hex: 0x2A2340) : .white) : pal.ink)
                        .background(Circle().fill(on ? pal.accent : pal.ink.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Song

struct SongCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var pal

    var label: String {
        guard let f = model.nextFire else { return "NEXT SONG" }
        let cal = Calendar.current
        if cal.isDateInToday(f) { return "TODAY'S SONG" }
        if cal.isDateInTomorrow(f) { return "TOMORROW'S SONG" }
        return f.formatted(.dateTime.weekday(.wide)).uppercased() + "'S SONG"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(label).font(.system(size: 11, weight: .semibold)).tracking(1.6).foregroundStyle(pal.sub)
                Spacer()
                if model.preparing { ProgressView().controlSize(.small) }
            }
            if let p = model.pick {
                HStack(alignment: .top, spacing: 16) {
                    Artwork(url: p.artworkURL, size: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title).font(.serif(23, .medium)).lineLimit(2)
                        Text(p.artist).font(.system(size: 14)).foregroundStyle(pal.sub)
                        if !p.mood.isEmpty {
                            Text(p.mood).font(.system(size: 11, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 3)
                                .background(Capsule().fill(pal.accent.opacity(0.22))).padding(.top, 3)
                        }
                    }
                }
                if !p.why.isEmpty {
                    Text(p.why).font(.serif(15)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    PillButton(title: "Hear a bit", icon: "play.fill") { model.player.previewOnly(p) }
                    PillButton(title: "Another one", icon: "arrow.triangle.2.circlepath") { model.reroll() }
                    Menu {
                        if let s = p.storeURL, let u = URL(string: s) { Button("Apple Music") { NSWorkspace.shared.open(u) } }
                        Button("Spotify") { open("spotify:search:" + q(p)) }
                        Button("YouTube") { open("https://www.youtube.com/results?search_query=" + q(p)) }
                    } label: {
                        Text("Open in…").font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(pal.ink.opacity(0.07)))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    Spacer()
                }
                Text(p.refined ? "Locked in with the latest forecast." : "A draft. It locks in tonight, once the forecast is firm.")
                    .font(.system(size: 11)).foregroundStyle(pal.sub)
            } else {
                Text(model.preparing ? "Reading the sky…" : "Turn the alarm on and I'll pick something.")
                    .font(.serif(17)).foregroundStyle(pal.sub).padding(.vertical, 18)
            }
            if !model.note.isEmpty {
                Text(model.note).font(.system(size: 11)).foregroundStyle(pal.sub)
            } else if model.pick != nil {
                Text("From \(Catalog.songs.count) songs, matched to the sky and weather.").font(.system(size: 11)).foregroundStyle(pal.sub)
            }
        }
        .card()
    }

    func q(_ p: SongPick) -> String {
        "\(p.title) \(p.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }
    func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
}

struct Artwork: View {
    @Environment(\.palette) var pal
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }

    var placeholder: some View {
        ZStack {
            LinearGradient(colors: [pal.accent.opacity(0.7), pal.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note").font(.system(size: size * 0.32)).foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Sky

struct SkyCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var pal
    @State private var showNow: Bool
    let openSettings: () -> Void

    init(startNow: Bool = false, openSettings: @escaping () -> Void) {
        _showNow = State(initialValue: startNow)
        self.openSettings = openSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(showNow ? "THE SKY RIGHT NOW" : "THE SKY AT WAKE-UP").font(.system(size: 11, weight: .semibold)).tracking(1.6).foregroundStyle(pal.sub)
                Spacer()
                Picker("", selection: $showNow) {
                    Text("Wake-up").tag(false)
                    Text("Now").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            TimelineView(.everyMinute) { ctx in
                let s = showNow ? model.makeSky(at: ctx.date) : model.sky
                let w = showNow ? model.weatherNow : model.weather
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 18) {
                        vedic(s)
                        Divider().overlay(pal.ink.opacity(0.08))
                        weatherBlock(w)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if let f = showNow ? ctx.date : model.nextFire {
                        Label(showNow ? "It's \(f.formatted(date: .omitted, time: .shortened)) · \(f.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
                                      : "Alarm \(f.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(f.formatted(date: .omitted, time: .shortened))",
                              systemImage: "clock")
                            .font(.system(size: 13, weight: .medium)).padding(.top, 2)
                    }
                }
            }
            if !model.settings.hasBirth || !model.settings.birthPlace.resolved {
                Button(action: openSettings) {
                    Label("Add your birth details for a personal chart", systemImage: "sparkles").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(pal.accent)
            }
        }
        .card()
    }

    func vedic(_ sky: SkyReport?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = sky {
                Text("Moon in \(s.nakshatra)").font(.serif(18, .medium))
                Text("pada \(s.moon.pada) · \(s.moonSignName.components(separatedBy: " ").first ?? "")").font(.system(size: 12)).foregroundStyle(pal.sub)
                line("moon.stars", "\(s.paksha.components(separatedBy: " ").first ?? "") \(s.tithiName)")
                line("calendar", s.vara.components(separatedBy: " ").first ?? "")
                if let n = s.natal {
                    line("hourglass", "\(n.maha) / \(n.antar) dasha")
                    line("circle.hexagongrid", "Tara: \(s.taraName ?? "")")
                    if n.sadeSati { line("moon.zzz", "Sade Sati") }
                }
            } else {
                Text("…").foregroundStyle(pal.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func weatherBlock(_ weather: WeatherSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let w = weather {
                HStack(spacing: 8) {
                    Image(systemName: w.symbol).symbolRenderingMode(.hierarchical).font(.system(size: 24)).foregroundStyle(pal.accent)
                    Text("\(Int(w.temp.rounded()))°").font(.serif(30, .light))
                }
                Text(w.summary.capitalized).font(.system(size: 13))
                Text(w.placeName).font(.system(size: 12)).foregroundStyle(pal.sub)
                if let sr = w.sunrise { line("sunrise", "Sunrise \(sr)") }
                if showNow, let ss = w.sunset { line("sunset", "Sunset \(ss)") }
                if w.precipProb >= 20 { line("drop", "\(w.precipProb)% rain") }
            } else if model.settings.city.resolved {
                ProgressView().controlSize(.small)
            } else {
                Text("Set your city in Settings to bring the weather in.").font(.system(size: 12)).foregroundStyle(pal.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func line(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(pal.sub).frame(width: 14)
            Text(text).font(.system(size: 13))
        }
    }
}

// MARK: - Menu bar

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow

    var body: some View {
        if model.settings.enabled, let f = model.nextFire {
            Text("Next: " + f.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
        } else {
            Text("Alarm is off")
        }
        if let p = model.pick { Text("\(p.title) — \(p.artist)") }
        Divider()
        Button("Open Subah") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Try it now") { model.ring(testing: true) }
        Divider()
        Button("Quit Subah") { NSApp.terminate(nil) }
    }
}
