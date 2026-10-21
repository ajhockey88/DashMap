import SwiftUI
import MapKit
import CoreLocation

struct RootView: View {
    @EnvironmentObject private var session: NavigationSession
    @StateObject private var search = PlaceSearch()
    @StateObject private var places = PlacesStore()
    @State private var query = ""
    @State private var showSettings = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if session.phase == .preview {
                PreviewView()
            } else {
                home
            }
        }
        .fullScreenCover(isPresented: .constant(session.phase == .navigating)) {
            NavigationScreen().environmentObject(session)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(session)
        }
        .alert("Navigation", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: Home

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Where to?").font(.largeTitle.bold())
                    Spacer()
                    IconButton(systemName: "gearshape.fill", label: "Settings") { showSettings = true }
                }

                searchField
                LocationBanner(location: session.location)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    shortcuts
                    savedPlaces
                    recents
                } else {
                    results
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if session.phase == .loading {
                ProgressView("Finding route…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
            TextField("Search address or place", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newValue in search.update(query: newValue, near: session.location.location?.coordinate) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var shortcuts: some View {
        if places.home != nil || places.work != nil {
            HStack(spacing: 12) {
                if let home = places.home { chip("Home", "house.fill", home) }
                if let work = places.work { chip("Work", "briefcase.fill", work) }
            }
        }
    }

    private func chip(_ title: String, _ icon: String, _ place: SavedPlace) -> some View {
        Button { go(place.mapItem) } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(Theme.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var savedPlaces: some View {
        if !places.saved.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
                ForEach(places.saved) { place in
                    Button { go(place.mapItem) } label: {
                        row(icon: "star.fill", title: place.name, subtitle: place.subtitle)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Set as Home", systemImage: "house") { places.setHome(place) }
                        Button("Set as Work", systemImage: "briefcase") { places.setWork(place) }
                        Button("Remove from Saved", systemImage: "star.slash", role: .destructive) { places.removeSaved(place) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var recents: some View {
        if places.recents.isEmpty && places.saved.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "location.north.line.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                Text("Search for a destination to start.").foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if !places.recents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
                ForEach(places.recents) { place in
                    Button { go(place.mapItem) } label: {
                        row(icon: "clock.arrow.circlepath", title: place.name, subtitle: place.subtitle)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if places.isSaved(place) {
                            Button("Remove from Saved", systemImage: "star.slash") { places.removeSaved(place) }
                        } else {
                            Button("Save", systemImage: "star") { places.addSaved(place) }
                        }
                        Button("Set as Home", systemImage: "house") { places.setHome(place) }
                        Button("Set as Work", systemImage: "briefcase") { places.setWork(place) }
                        Button("Remove", systemImage: "trash", role: .destructive) { places.remove(place) }
                    }
                }
                Text("Touch and hold a place to save it or set it as Home or Work.")
                    .font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 4)
            }
        }
    }

    private var results: some View {
        VStack(spacing: 8) {
            ForEach(search.results, id: \.self) { result in
                Button {
                    Task {
                        guard let item = try? await search.resolve(result) else { return }
                        go(item)
                    }
                } label: {
                    row(icon: "mappin", title: result.title, subtitle: result.subtitle)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Save", systemImage: "star") {
                        Task {
                            guard let item = try? await search.resolve(result) else { return }
                            places.addSaved(SavedPlace(item: item))
                        }
                    }
                }
            }
        }
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
        }
        .padding(14)
        .frame(minHeight: 60)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }

    private func go(_ item: MKMapItem) {
        searchFocused = false
        places.addRecent(SavedPlace(item: item))
        query = ""
        Task { await session.plan(to: item) }
    }
}

/// Explains location problems instead of leaving the user with a search box that silently can't route.
private struct LocationBanner: View {
    @ObservedObject var location: LocationService
    @Environment(\.openURL) private var openURL

    var body: some View {
        if location.authorization == .denied || location.authorization == .restricted {
            HStack(spacing: 12) {
                Image(systemName: "location.slash.fill").foregroundStyle(Theme.danger)
                Text("Location is off. DashMap needs it to guide you.").font(.subheadline)
                Spacer()
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        } else if location.location == nil {
            HStack(spacing: 10) {
                ProgressView()
                Text("Finding your location…").font(.subheadline).foregroundStyle(Theme.secondary)
            }
        }
    }
}
