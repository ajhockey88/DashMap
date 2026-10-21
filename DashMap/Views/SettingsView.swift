import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var session: NavigationSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var units = "auto"
    @AppStorage("nav.hud") private var startInHUD = false
    @AppStorage("hud.style") private var hudStyle = "arrows"
    @AppStorage("hud.mirrored") private var mirrored = true
    @AppStorage(Voice.voiceKey) private var voiceID = ""
    @AppStorage(Voice.rateKey) private var voiceRate = Voice.defaultRate
    @State private var previewVoice = Voice()
    private let voices = Voice.availableVoices()

    private func label(for v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: return "\(v.name) (Premium)"
        case .enhanced: return "\(v.name) (Enhanced)"
        default: return v.name
        }
    }

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
                Section {
                    Toggle("Voice guidance", isOn: $session.voiceEnabled)
                    Picker("Voice", selection: $voiceID) {
                        Text("Best available").tag("")
                        ForEach(voices, id: \.identifier) { v in
                            Text(label(for: v)).tag(v.identifier)
                        }
                    }
                    HStack {
                        Image(systemName: "tortoise.fill").foregroundStyle(Theme.secondary)
                        Slider(value: $voiceRate, in: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate))
                            .accessibilityLabel("Speaking speed")
                        Image(systemName: "hare.fill").foregroundStyle(Theme.secondary)
                    }
                    Button("Preview voice", systemImage: "play.circle.fill") { previewVoice.preview() }
                } header: {
                    Text("Guidance")
                } footer: {
                    Text("For a more natural voice, download an Enhanced or Premium one in the iPhone Settings app under Accessibility, Spoken Content, Voices. It then shows up in this list.")
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
                Section("About") {
                    Text("Lane guidance, road names and speed limits use OpenStreetMap data where it has been mapped. © OpenStreetMap contributors.")
                        .font(.footnote)
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
