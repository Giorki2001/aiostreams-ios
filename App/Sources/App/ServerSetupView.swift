import SwiftUI

/// Asks once for the AIOStreams instance whose web app the app shows.
struct ServerSetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var address = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.brand.opacity(0.45), Color.page, Color.page],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 30))

                VStack(spacing: 8) {
                    Text("AIOStreams")
                        .font(.largeTitle.bold())
                    Text("Incolla l'indirizzo della tua istanza, oppure il link «Open in browser» che trovi in Save & Install → AIOStreams app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("https://aiostreams.example.com", text: $address)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(connect)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .glassEffect(.regular.interactive(), in: .capsule)

                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(action: connect) {
                    Text("Connetti")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)

                if model.serverURL != nil {
                    Button("Annulla") { model.showServerSetup = false }
                        .buttonStyle(.glass)
                }
            }
            .padding(28)
            .frame(maxWidth: 480)
        }
        .onAppear {
            address = model.serverURL?.absoluteString ?? ""
            focused = model.serverURL == nil
        }
    }

    private func connect() {
        guard let url = Self.webAppURL(from: address) else {
            problem = "Non sembra un indirizzo valido."
            return
        }
        problem = nil
        model.connect(to: url)
    }

    /// The web app lives at `/jellyfin/web/` (or `/jellyfin/u/<name>/web/` for a user's own link).
    static func webAppURL(from text: String) -> URL? {
        var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }
        if !string.contains("://") { string = "https://" + string }
        guard var components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else { return nil }
        var path = components.path
        if path.hasSuffix("/index.html") { path.removeLast("index.html".count) }
        if !path.contains("/web") {
            if !path.hasSuffix("/") { path += "/" }
            if !path.contains("/jellyfin") { path += "jellyfin/" }
            path += "web/"
        } else if !path.hasSuffix("/") {
            path += "/"
        }
        components.path = path
        components.fragment = nil
        return components.url
    }
}
