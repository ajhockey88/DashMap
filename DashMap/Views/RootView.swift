import SwiftUI
import DashMapCore

struct RootView: View {
    @EnvironmentObject private var session: NavigationSession
    @State private var query = ""
    @State private var suggestions: [PlaceSuggestion] = []

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .preview, .navigating:
                    PreviewView()
                default:
                    searchList
                }
            }
            .navigationTitle("DashMap")
        }
        .fullScreenCover(isPresented: .constant(session.phase == .navigating)) {
            HUDView().environmentObject(session)
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

    private var searchList: some View {
        List {
            if session.phase == .loading { ProgressView("Finding route…") }
            ForEach(suggestions) { place in
                Button(place.title) {
                    Task { await session.plan(to: .placeId(place.id)) }
                }
            }
        }
        .searchable(text: $query, prompt: "Where to?")
        .task(id: query) {
            guard query.count >= 3 else { suggestions = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)   // debounce; cancelled by .task(id:)
            guard !Task.isCancelled else { return }
            suggestions = (try? await PlacesAPI.autocomplete(query, near: session.currentCoordinate)) ?? []
        }
    }
}
