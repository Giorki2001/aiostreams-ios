import AetherEngine
import SwiftUI

/// The video at the bottom, its subtitles, the web app over both, and the
/// native controls in Liquid Glass on top.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.page.ignoresSafeArea()

            AetherPlayerSurface(engine: model.engine)
                .ignoresSafeArea()
                .opacity(model.playerActive ? 1 : 0)

            if model.playerActive {
                SubtitleOverlay(
                    engine: model.engine,
                    clock: model.engine.clock,
                    style: model.subtitleStyle,
                    delayMs: model.subtitleDelayMs
                )
                .ignoresSafeArea()
            }

            WebViewContainer(host: model.web)
                .ignoresSafeArea()

            if model.playerActive {
                VolumeViewHost(levels: model.levels)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }

            overlays
        }
        .statusBarHidden(model.fullscreen)
        .persistentSystemOverlays(model.fullscreen ? .hidden : .automatic)
        .fullScreenCover(isPresented: $model.showServerSetup) {
            ServerSetupView()
                .environmentObject(model)
        }
    }

    @ViewBuilder
    private var overlays: some View {
        if model.navVisible && !model.playerActive && !model.navItems.isEmpty {
            GlassTabBar(
                items: model.navItems,
                select: { model.select(tab: $0) },
                changeServer: { model.showServerSetup = true },
                reload: { model.reload() },
                exportLog: { model.exportLog() }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.keyboard)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if model.playerActive {
            playerOverlays
        }

        if model.statsVisible {
            StatsOverlay(engine: model.engine)
                .padding(.top, 64)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        if let error = model.loadError {
            LoadErrorCard(
                message: error,
                retry: { model.reload() },
                changeServer: { model.showServerSetup = true }
            )
            .padding(24)
        }
    }
}

extension RootView {
    /// AirPlay and PiP sit in the room the page leaves in its top bar and come and go
    /// with its controls; the volume and AirPlay notices sit at the top centre.
    @ViewBuilder
    var playerOverlays: some View {
        let chrome = model.playerChrome
        GeometryReader { _ in
            if let slot = chrome.slot {
                PlayerButtons(pip: model.pip)
                    .frame(width: slot.width, height: 44, alignment: .trailing)
                    .position(x: slot.x + slot.width / 2, y: slot.y)
                    .opacity(chrome.visible ? 1 : 0)
                    .allowsHitTesting(chrome.visible)
                    .animation(.easeInOut(duration: 0.3), value: chrome.visible)
            }
        }
        .ignoresSafeArea()

        VStack(spacing: 10) {
            VolumeHUD(levels: model.levels)
            if chrome.visible {
                AirPlayNotice(engine: model.engine)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.3), value: chrome.visible)
    }
}

/// The server didn't answer.
private struct LoadErrorCard: View {
    let message: String
    let retry: () -> Void
    let changeServer: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.brand)
            Text("Server non raggiungibile")
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Cambia server", action: changeServer)
                        .buttonStyle(.glass)
                    Button("Riprova", action: retry)
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }
}
