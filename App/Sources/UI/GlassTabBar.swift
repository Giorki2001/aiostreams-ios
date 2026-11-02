import SwiftUI

/// The page's tabs as an iOS 26 tab bar in Liquid Glass: the sections in one
/// capsule, search apart in its own circle, the selection sliding between tabs.
struct GlassTabBar: View {
    let items: [NavItem]
    let select: (NavItem) -> Void
    let changeServer: () -> Void
    let reload: () -> Void
    let exportLog: () -> Void
    @Namespace private var selection

    var body: some View {
        let sections = items.filter { $0.id != "search" }
        let search = items.first { $0.id == "search" }
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(sections) { item in
                        tab(item)
                    }
                }
                .padding(4)
                .glassEffect(.regular.interactive(), in: .capsule)

                if let search {
                    Button { select(search) } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(search.current ? Color.brand : Color.primary)
                            .frame(width: 62, height: 62)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(search.label)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: items)
    }

    @ViewBuilder
    private func tab(_ item: NavItem) -> some View {
        let button = Button { select(item) } label: {
            VStack(spacing: 2) {
                Image(systemName: Self.symbol(for: item.id))
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 24)
                Text(item.label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(item.current ? Color.brand : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if item.current {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(item.current ? .isSelected : [])

        if item.id == "account" {
            button.contextMenu {
                Button("Cambia server", systemImage: "server.rack", action: changeServer)
                Button("Ricarica", systemImage: "arrow.clockwise", action: reload)
                Button("Esporta log del player", systemImage: "doc.text", action: exportLog)
            }
        } else {
            button
        }
    }

    static func symbol(for id: String) -> String {
        switch id {
        case "home": return "house.fill"
        case "discover": return "safari.fill"
        case "search": return "magnifyingglass"
        case "favourites": return "heart.fill"
        case "calendar": return "calendar"
        case "playlists": return "list.bullet"
        case "activity": return "clock.arrow.circlepath"
        case "downloads": return "arrow.down.circle.fill"
        case "party": return "person.2.fill"
        case "account": return "person.crop.circle.fill"
        default: return "square.grid.2x2.fill"
        }
    }
}
