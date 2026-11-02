import AetherEngine
import Combine
import SwiftUI
import UIKit

/// A tab of the page's navigation bar, which the native tab bar mirrors.
struct NavItem: Identifiable, Equatable, Decodable {
    let id: String
    let label: String
    let current: Bool
}

private struct NavState: Decodable {
    let visible: Bool
    let items: [NavItem]
}

/// Everything the app's views show, and the parts that talk to the page and the player.
@MainActor
final class AppModel: ObservableObject {
    private static let serverKey = "serverURL"

    @Published private(set) var serverURL: URL?
    @Published var showServerSetup = false
    @Published private(set) var navItems: [NavItem] = []
    @Published private(set) var navVisible = false
    @Published private(set) var fullscreen = false
    @Published var controlsShown = true
    @Published var playerActive = false
    @Published var statsVisible = false
    @Published var loadError: String?
    @Published var subtitleStyle = SubtitleStyle()
    @Published var subtitleDelayMs: Double = 0

    let engine: AetherEngine
    let bridge: AppBridge
    let player: PlayerChannel
    let web: WebViewHost
    let pip: PictureInPicture
    let nowPlaying: NowPlaying
    let levels = Levels()

    /// A link the app was opened with before the page could take it.
    private var pendingLink: String?
    private var linksReady = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        let engine: AetherEngine
        do {
            engine = try AetherEngine()
        } catch {
            fatalError("AetherEngine could not start: \(error)")
        }
        engine.backgroundPlaybackEnabled = true
        self.engine = engine
        let bridge = AppBridge()
        self.bridge = bridge
        player = PlayerChannel(engine: engine, bridge: bridge)
        web = WebViewHost(bridge: bridge)
        pip = PictureInPicture(engine: engine, bridge: bridge)
        nowPlaying = NowPlaying(engine: engine, bridge: bridge)

        bridge.model = self
        player.model = self
        web.model = self

        if let saved = UserDefaults.standard.string(forKey: Self.serverKey), let url = URL(string: saved) {
            serverURL = url
            web.load(url)
        } else {
            showServerSetup = true
        }

        $playerActive
            .removeDuplicates()
            .sink { [weak self] active in
                MainActor.assumeIsolated { self?.web.playerActive(active) }
            }
            .store(in: &cancellables)
    }

    // MARK: Server

    /// Saves the server and loads its web app.
    func connect(to url: URL) {
        serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.serverKey)
        loadError = nil
        showServerSetup = false
        web.load(url)
    }

    func reload() {
        loadError = nil
        if let serverURL { web.load(serverURL) }
    }

    // MARK: Navigation

    func updateNav(json: String) {
        guard let data = json.data(using: .utf8),
              let state = try? JSONDecoder().decode(NavState.self, from: data) else { return }
        if navItems != state.items { navItems = state.items }
        if navVisible != state.visible { navVisible = state.visible }
    }

    func select(tab: NavItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        web.tap(navItem: tab.id)
    }

    // MARK: Full screen

    func setFullscreen(_ on: Bool) {
        guard fullscreen != on else {
            bridge.send(["type": "fullscreen", "value": on])
            return
        }
        fullscreen = on
        Orientation.apply(landscape: on)
        bridge.send(["type": "fullscreen", "value": on])
    }

    // MARK: Links

    func open(link url: URL) {
        guard url.scheme == "aiostreams" else { return }
        if linksReady {
            bridge.send(["type": "link", "url": url.absoluteString])
        } else {
            pendingLink = url.absoluteString
        }
    }

    func pageWantsLinks() {
        linksReady = true
        if let link = pendingLink {
            pendingLink = nil
            bridge.send(["type": "link", "url": link])
        }
    }

    /// A new page starts with no links taken yet.
    func pageLoaded() {
        linksReady = false
        loadError = nil
    }
}
