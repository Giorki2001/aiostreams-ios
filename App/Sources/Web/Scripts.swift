import Foundation

/// The scripts the app adds to every page of the web app.
enum Scripts {
    /// `window.aiostreamsApp`, as the Android app defines it: protocol 2, the
    /// platform the page treats as a phone app, a `send` and a `subscribe`.
    static func bridge(identity: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: identity)) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return #"""
        (() => {
          if (window.top !== window || window.aiostreamsApp) return;
          const handlers = window.webkit && window.webkit.messageHandlers;
          if (!handlers || !handlers.aiostreams) return;
          const identity = \#(json);
          const listeners = new Set();
          Object.defineProperty(window, '__aiostreamsDeliver', {
            value: (message) => {
              for (const listener of listeners) {
                try { listener(message); } catch (error) { console.error(error); }
              }
            },
          });
          const send = (message) => handlers.aiostreams.postMessage(JSON.stringify(message));
          window.aiostreamsApp = Object.freeze({
            protocol: 2,
            version: identity.version,
            platform: 'android',
            tv: false,
            voice: false,
            gamepads: false,
            pip: true,
            device: identity.device,
            deviceId: identity.deviceId,
            send,
            subscribe(listener) {
              listeners.add(listener);
              return () => listeners.delete(listener);
            },
          });
          send({ type: 'hello' });
        })();
        """#
    }

    /// Hides the page's own tab bar (the app draws it natively) without taking it
    /// out of the layout, so menus it opens still anchor where the native bar is;
    /// reports its tabs to the app; keeps pinches and long presses from acting like a browser.
    static let chrome = #"""
    (() => {
      if (window.top !== window) return;
      const handlers = window.webkit && window.webkit.messageHandlers;
      if (!handlers || !handlers.aiostreamsNav) return;

      const style = document.createElement('style');
      style.textContent = `
        [data-ui="mobile-nav"] { opacity: 0 !important; }
        [data-ui="mobile-nav"], [data-ui="mobile-nav"] * { pointer-events: none !important; }
        html { -webkit-touch-callout: none; -webkit-text-size-adjust: 100%; }
        * { -webkit-tap-highlight-color: transparent; }
      `;
      document.documentElement.appendChild(style);

      let last = '';
      const read = () => {
        const nav = document.querySelector('[data-ui="mobile-nav"]');
        let visible = false;
        let items = [];
        if (nav) {
          visible = getComputedStyle(nav).display !== 'none' && nav.getClientRects().length > 0;
          items = Array.from(nav.querySelectorAll('button[data-name]')).map((button) => ({
            id: button.dataset.name,
            label: (button.textContent || '').trim() || button.getAttribute('aria-label') || '',
            current: button.getAttribute('aria-current') === 'page',
          }));
        }
        const state = JSON.stringify({ visible, items });
        if (state !== last) {
          last = state;
          handlers.aiostreamsNav.postMessage(state);
        }
      };
      let timer = 0;
      const soon = () => {
        clearTimeout(timer);
        timer = setTimeout(read, 60);
      };
      Object.defineProperty(window, '__aiostreamsTap', {
        value: (id) => {
          const button = document.querySelector('[data-ui="mobile-nav"] button[data-name="' + CSS.escape(id) + '"]');
          if (button) button.click();
        },
      });
      const start = () => {
        const viewport = document.querySelector('meta[name="viewport"]');
        if (viewport && !/user-scalable/.test(viewport.content)) {
          viewport.content += ', maximum-scale=1, user-scalable=no';
        }
        new MutationObserver(soon).observe(document.body, {
          subtree: true,
          childList: true,
          attributes: true,
          attributeFilter: ['aria-current', 'data-name'],
        });
        window.addEventListener('hashchange', soon);
        window.addEventListener('resize', soon);
        read();
      };
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
      else start();
    })();
    """#
}
