import AVFoundation
import AppKit
import SwiftUI
import WebKit

/// Plays the chosen song. Chain: YouTube (in-app, full song) -> iTunes 30s preview loop -> system chime.
@MainActor
final class PlayerService: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var status = ""
    @Published var showsVideo = false

    let webView: WKWebView
    private var avPlayer: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var chime: NSSound?
    private var waiter: CheckedContinuation<Bool, Never>?
    private var playToken = UUID()
    var muted = false // test-only

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 180), configuration: cfg)
        super.init()
        webView.configuration.userContentController.add(self, name: "yt")
        webView.setValue(false, forKey: "drawsBackground")
    }

    // MARK: WKScriptMessageHandler

    nonisolated func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let ev = body["event"] as? String else { return }
        let info = body["info"] as? Int
        Task { @MainActor in self.handle(event: ev, info: info) }
    }

    private func handle(event: String, info: Int?) {
        switch event {
        case "state" where info == 1: finishWait(true)      // playing
        case "error": finishWait(false)
        default: break
        }
    }

    private func finishWait(_ ok: Bool) {
        waiter?.resume(returning: ok)
        waiter = nil
    }

    // MARK: Play

    func play(_ pick: SongPick) async {
        stop()
        let token = UUID()
        playToken = token
        status = "Finding \(pick.title)…"

        let ids = await YouTube.search(title: pick.title, artist: pick.artist, durationMs: pick.durationMs)
        for id in ids {
            guard playToken == token else { return }
            status = "Tuning in…"
            if await loadYouTube(id) {
                status = "Playing from YouTube"
                showsVideo = true
                return
            }
        }
        guard playToken == token else { return }
        webView.loadHTMLString("", baseURL: nil)
        showsVideo = false

        if let p = pick.previewURL, let url = URL(string: p) {
            status = "Playing a 30-second preview (full song wasn't reachable)"
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                player.seek(to: .zero)
                player.play()
            }
            avPlayer = player
            player.play()
            return
        }
        status = "Offline — playing a soft chime"
        chime = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: true)
        chime?.loops = true
        chime?.play()
    }

    private func loadYouTube(_ id: String) async -> Bool {
        finishWait(false)
        let html = """
        <html><body style="margin:0;background:#000;overflow:hidden"><div id="p"></div><script>
        function post(o){window.webkit.messageHandlers.yt.postMessage(o)}
        var player;
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('p',{width:'100%',height:'100%',videoId:'\(id)',
            playerVars:{autoplay:1,controls:0,rel:0,playsinline:1,modestbranding:1,iv_load_policy:3},
            events:{
              onReady:function(e){e.target.setVolume(100);\(muted ? "e.target.mute();" : "")e.target.playVideo();post({event:'ready'})},
              onStateChange:function(e){ if(e.data===0){player.seekTo(0);player.playVideo()} post({event:'state',info:e.data})},
              onError:function(e){post({event:'error',info:e.data})}}})}
        var s=document.createElement('script');s.src='https://www.youtube.com/iframe_api';
        s.onerror=function(){post({event:'error',info:-1})};document.head.appendChild(s);
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://subah.app"))
        return await withCheckedContinuation { cont in
            waiter = cont
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 14_000_000_000)
                if self.waiter != nil { self.finishWait(false) }
            }
        }
    }

    func stop() {
        playToken = UUID()
        finishWait(false)
        webView.loadHTMLString("", baseURL: nil)
        showsVideo = false
        avPlayer?.pause()
        avPlayer = nil
        if let o = loopObserver { NotificationCenter.default.removeObserver(o); loopObserver = nil }
        chime?.stop()
        chime = nil
        status = ""
    }

    /// 30-second preview for the "Hear a bit" button.
    func previewOnly(_ pick: SongPick) {
        stop()
        guard let p = pick.previewURL, let url = URL(string: p) else { status = "No preview available"; return }
        let player = AVPlayer(url: url)
        avPlayer = player
        player.play()
        status = "Preview"
    }
}

struct PlayerWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// System-volume helpers: gentle fade-in so the song never blasts you awake.
@MainActor
final class VolumeRamp {
    private var timer: Timer?

    static func set(_ v: Int) {
        let script = NSAppleScript(source: "set volume without output muted\nset volume output volume \(max(0, min(100, v)))")
        var err: NSDictionary?
        script?.executeAndReturnError(&err)
    }

    func fade(to target: Int, over seconds: Int) {
        timer?.invalidate()
        let start = min(12, target)
        VolumeRamp.set(start)
        guard seconds > 0, target > start else { VolumeRamp.set(target); return }
        let began = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            let f = min(1, Date().timeIntervalSince(began) / Double(seconds))
            let eased = f * f * (3 - 2 * f) // smoothstep
            VolumeRamp.set(start + Int(Double(target - start) * eased))
            if f >= 1 { t.invalidate(); self?.timer = nil }
        }
    }

    func cancel() { timer?.invalidate(); timer = nil }
}
