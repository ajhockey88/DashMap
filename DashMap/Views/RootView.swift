import SwiftUI
import MapKit
import DashMapCore

struct RootView: View {
    @EnvironmentObject private var session: NavigationSession
    @State private var query = ""
    @StateObject private var search = PlaceSearch()

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
            NavigationScreen().environmentObject(session)
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
            ForEach(search.results, id: \.self) { place in
                Button {
                    Task {
                        guard let item = try? await search.resolve(place) else { return }
                        await session.plan(to: item)
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(place.title)
                        if !place.subtitle.isEmpty { Text(place.subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Where to?")
        .onChange(of: query) { search.update(query: $0, near: session.location.location?.coordinate) }
    }
}
