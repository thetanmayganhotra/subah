import AppKit
import SwiftUI

final class RingWindowController {
    private var window: NSWindow?

    @MainActor
    func show(_ model: AppModel) {
        if window != nil { hide() }
        let host = NSHostingView(rootView: RingView().environmentObject(model))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 860),
                         styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    @MainActor
    func hide() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }
}

struct RingView: View {
    @EnvironmentObject var model: AppModel
    @State private var glow = false
    private let pal = Palette.dawn

    var body: some View {
        ZStack {
            SkyBackground(palette: pal)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFE6B8, opacity: 0.85), .clear], center: .center, startRadius: 0, endRadius: 300))
                .frame(width: 620, height: 620)
                .scaleEffect(glow ? 1.12 : 0.92)
                .offset(y: -330)
                .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: glow)

            VStack(spacing: 18) {
                Spacer(minLength: 24)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ctx.date.formatted(date: .omitted, time: .shortened))
                        .font(.serif(76, .ultraLight)).monospacedDigit()
                }
                Text(greeting).font(.serif(22)).italic().multilineTextAlignment(.center).foregroundStyle(pal.ink.opacity(0.85))

                songBlock

                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    PillButton(title: "Snooze \(model.settings.snoozeMinutes) min", icon: "zzz") { model.snooze() }
                    PillButton(title: "I'm up", icon: "sun.max", filled: true) { model.stopAlarm() }
                }
                Spacer(minLength: 26)
            }
            .padding(.horizontal, 36)
            .environment(\.palette, pal)
        }
        .foregroundStyle(pal.ink)
        .preferredColorScheme(.light)
        .frame(width: 620, height: 860)
        .onAppear { glow = true }
    }

    var greeting: String {
        if let g = model.ringPick?.greeting, !g.isEmpty { return g }
        let g = timeGreeting(Date(), tz: model.settings.city.resolved ? model.settings.city.timeZone : .current)
        return model.settings.userName.isEmpty ? "\(g)." : "\(g), \(model.settings.userName)."
    }

    var songBlock: some View {
        VStack(spacing: 14) {
            if let p = model.ringPick {
                HStack(spacing: 16) {
                    Artwork(url: p.artworkURL, size: 104)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title).font(.serif(24, .medium)).lineLimit(2)
                        Text(p.artist).font(.system(size: 14)).foregroundStyle(pal.sub)
                        Text(model.player.status).font(.system(size: 11)).foregroundStyle(pal.sub).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                if !p.why.isEmpty {
                    Text(p.why).font(.serif(15)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.ringPhase.isEmpty ? "Choosing something gentle…" : model.ringPhase).font(.serif(16)).foregroundStyle(pal.sub)
                }
                .padding(.vertical, 24)
            }
            // The player has to live in a window to autoplay; it stays here, faded in once the song starts.
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.ink.opacity(0.06))
                Image(systemName: "waveform").font(.system(size: 26, weight: .ultraLight)).foregroundStyle(pal.sub)
                PlayerWebView(webView: model.player.webView)
                    .opacity(model.player.showsVideo ? 1 : 0.02)
                    .animation(.easeInOut(duration: 1.2), value: model.player.showsVideo)
                    .allowsHitTesting(false)
            }
            .frame(width: 320, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .card()
    }
}
