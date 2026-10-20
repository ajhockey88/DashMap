import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: NavigationSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var units = "auto"
    @AppStorage("nav.hud") private var startInHUD = false
    @AppStorage("hud.style") private var hudStyle = "arrows"
    @AppStorage("hud.mirrored") private var mirrored = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Distance and speed", selection: $units) {
                        Text("Automatic").tag("auto")
                        Text("Miles").tag("imperial")
                        Text("Kilometers").tag("metric")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Guidance") {
                    Toggle("Voice guidance", isOn: $session.voiceEnabled)
                }
                Section {
                    Picker("Start with", selection: $startInHUD) {
                        Text("Map").tag(false)
                        Text("HUD").tag(true)
                    }
                    Picker("HUD style", selection: $hudStyle) {
                        Text("Arrows and text").tag("arrows")
                        Text("Moving map").tag("map")
                    }
                    Toggle("Mirror HUD for windshield", isOn: $mirrored)
                } header: {
                    Text("Display")
                } footer: {
                    Text("Lay the phone flat on the dashboard, screen up, with mirroring on. Turn mirroring off to read the HUD directly.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
