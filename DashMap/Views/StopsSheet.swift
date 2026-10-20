import SwiftUI
import MapKit
import DashMapCore

/// Search along the route and add a stop without leaving navigation.
struct StopsSheet: View {
    @EnvironmentObject private var session: NavigationSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var unitsSetting = "auto"
    @StateObject private var finder = StopFinder()
    @State private var category: StopCategory?
    @State private var plan: StopPlan?
    @State private var isRouting = false

    private var units: Units { Units(setting: unitsSetting) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(StopCategory.allCases) { c in
                            Button { choose(c) } label: {
                                Label(c.title, systemImage: c.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(category == c ? Theme.onAccent : .white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 44)
                                    .background(category == c ? Theme.accent : Theme.surfaceRaised, in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if finder.isSearching || isRouting {
                    ProgressView(isRouting ? "Adding stop…" : "Searching along your route…")
                        .frame(maxWidth: .infinity).padding(.top, 30)
                } else if category != nil, finder.results.isEmpty {
                    Text("Nothing found close to your route.")
                        .foregroundStyle(Theme.secondary).frame(maxWidth: .infinity).padding(.top, 30)
                } else {
                    List(finder.results) { result in
                        Button { Task { await prepare(result) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.item.name ?? "Place").font(.body.weight(.semibold))
                                    Text("\(units.distance(result.distanceAhead)) ahead · about \(result.roughDetourMinutes) min detour")
                                        .font(.footnote).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent).font(.title3)
                            }
                            .frame(minHeight: 44)
                        }
                        .listRowBackground(Theme.surface)
                    }
                    .listStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .background(Theme.background)
            .navigationTitle("Add a stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Close") { dismiss() } }
            .alert("Add stop?", isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } })) {
                Button("Add stop") {
                    if let plan { session.commitStop(plan) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { plan = nil }
            } message: {
                if let plan {
                    let minutes = max(0, Int((plan.added / 60).rounded()))
                    Text("\(plan.item.name ?? "This place") adds \(minutes) min to your trip.")
                }
            }
        }
    }

    private func choose(_ c: StopCategory) {
        category = c
        guard let route = session.route, let progress = session.state?.progress else { return }
        Task { await finder.search(c, route: route, progress: progress) }
    }

    private func prepare(_ result: StopResult) async {
        isRouting = true
        defer { isRouting = false }
        plan = await session.previewStop(result.item)
        if plan == nil { session.reportError("Couldn't route to that place.") }
    }
}
