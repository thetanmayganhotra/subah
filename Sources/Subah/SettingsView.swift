import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.palette) var pal

    @State private var draft = AlarmSettings()
    @State private var birthMsg = ""
    @State private var cityMsg = ""
    @State private var loaded = false

    var body: some View {
        ZStack {
            SkyBackground(palette: pal)
            VStack(spacing: 0) {
                HStack {
                    Text("Settings").font(.serif(26, .light)).italic()
                    Spacer()
                    PillButton(title: "Done", filled: true) { commit(); dismiss() }
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        whereSection
                        chartSection
                        soundSection
                        playlistSection
                        systemSection
                    }
                    .padding(.horizontal, 24).padding(.bottom, 28)
                }
            }
        }
        .frame(width: 540, height: 700)
        .foregroundStyle(pal.ink)
        .onAppear {
            guard !loaded else { return }
            draft = model.settings
            loaded = true
        }
    }

    func commit() {
        if draft != model.settings { model.settings = draft }
    }

    // MARK: sections

    var whereSection: some View {
        section("Where you wake up", "Weather for your wake-up hour comes from here.") {
            Toggle("Use my current location", isOn: $draft.autoLocate).toggleStyle(.switch).tint(pal.accent)
            if draft.autoLocate {
                Label(draft.city.resolved ? draft.city.name : "Detecting…", systemImage: "location.fill")
                    .font(.system(size: 12)).foregroundStyle(pal.accent)
                Text("Found from your internet connection, so it's accurate to the city. It updates when you travel.")
                    .font(.system(size: 11)).foregroundStyle(pal.sub)
            } else {
                placeRow(query: $draft.city.query, place: draft.city, message: cityMsg, placeholder: "City, e.g. Pune") {
                    find(draft.city.query) { draft.city = $0 } fail: { cityMsg = $0 }
                }
            }
        }
    }

    var chartSection: some View {
        section("Your Vedic chart", "Used only on this Mac to work out your sky. Sidereal, Lahiri, whole-sign houses.") {
            Toggle("Use my birth chart", isOn: $draft.hasBirth).toggleStyle(.switch).tint(pal.accent)
            if draft.hasBirth {
                TextField("Your name (optional)", text: $draft.userName).textFieldStyle(.roundedBorder)
                DatePicker("Born", selection: $draft.birthLocal, displayedComponents: [.date, .hourAndMinute])
                placeRow(query: $draft.birthPlace.query, place: draft.birthPlace, message: birthMsg, placeholder: "Birth city, e.g. Delhi") {
                    find(draft.birthPlace.query) { draft.birthPlace = $0 } fail: { birthMsg = $0 }
                }
                Text("Time is read as local time at your birthplace.").font(.system(size: 11)).foregroundStyle(pal.sub)
            }
        }
    }

    var soundSection: some View {
        section("Waking up", nil) {
            Toggle("Go to full volume automatically", isOn: $draft.fullVolume).toggleStyle(.switch).tint(pal.accent)
            slider("Volume", value: Binding(get: { Double(draft.fullVolume ? 100 : draft.volume) }, set: { draft.volume = Int($0) }), range: 20...100, suffix: "%")
                .opacity(draft.fullVolume ? 0.4 : 1).disabled(draft.fullVolume)
            slider("Fade in over", value: Binding(get: { Double(draft.fadeSeconds) }, set: { draft.fadeSeconds = Int($0) }), range: 0...300, suffix: " s")
            Text("Your Mac's volume rises from quiet to \(draft.fullVolume ? "100%" : "\(draft.volume)%") over this time, and un-mutes itself. Set 0 s for instant.")
                .font(.system(size: 11)).foregroundStyle(pal.sub)
            Stepper("Snooze: \(draft.snoozeMinutes) min", value: $draft.snoozeMinutes, in: 1...30)
        }
    }

    var playlistSection: some View {
        section("Playlist", nil) {
            let n = Catalog.songs.count
            Label("\(n) songs, hand-picked and checked", systemImage: "music.note.list")
                .font(.system(size: 13)).foregroundStyle(pal.accent)
            Text("Each morning's song is chosen from your sky and the weather. A song only comes back after nearly all of the others have played, about \(max(1, (n - 30) / 30)) months.")
                .font(.system(size: 11)).foregroundStyle(pal.sub)
        }
    }

    var systemSection: some View {
        section("Mac", nil) {
            Toggle("Open Subah when I log in", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                .toggleStyle(.switch).tint(pal.accent)
            Text("The app has to be running for the alarm to ring, so keep this on.").font(.system(size: 11)).foregroundStyle(pal.sub)
        }
    }

    // MARK: pieces

    func section<C: View>(_ title: String, _ hint: String?, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.6).foregroundStyle(pal.sub)
            content()
            if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(pal.sub) }
        }
        .card()
    }

    func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).frame(width: 90, alignment: .leading)
            Slider(value: value, in: range).tint(pal.accent)
            Text("\(Int(value.wrappedValue))\(suffix)").font(.system(size: 12)).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
    }

    func placeRow(query: Binding<String>, place: Place, message: String, placeholder: String, find: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(placeholder, text: query).textFieldStyle(.roundedBorder).onSubmit(find)
                PillButton(title: "Find", action: find)
            }
            if place.resolved {
                Label(place.name, systemImage: "mappin.and.ellipse").font(.system(size: 12)).foregroundStyle(pal.accent)
            } else if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundStyle(pal.sub)
            }
        }
    }

    func find(_ q: String, ok: @escaping (Place) -> Void, fail: @escaping (String) -> Void) {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        fail("Looking…")
        Task {
            do {
                var p = try await WeatherService.geocode(query)
                p.query = query
                ok(p)
                fail("")
            } catch {
                fail("Couldn't find “\(query)”. Try a nearby city.")
            }
        }
    }
}
