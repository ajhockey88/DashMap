import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var session: NavigationSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var units = "auto"
    @AppStorage("nav.hud") private var startInHUD = false
    @AppStorage("hud.style") private var hudStyle = "arrows"
    @AppStorage("hud.mirrored") private var mirrored = true
    @AppStorage("hud.flipped") private var flipped = false
    @AppStorage(Voice.voiceKey) private var voiceID = ""
    @AppStorage(Voice.rateKey) private var voiceRate = Voice.defaultRate
    @State private var previewVoice = Voice()
    @Environment(\.scenePhase) private var scenePhase
    @State private var voices = Voice.naturalVoices()

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
                    if voices.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Get a natural voice (free)", systemImage: "waveform").font(.headline)
                            Text("1. Open the iPhone Settings app.\n2. Go to Accessibility, then Spoken Content, then Voices.\n3. Pick your language and download a Premium or Enhanced voice (for example Ava, Zoe or Evan).\n4. Come back here and it appears in this list.")
                                .font(.footnote).foregroundStyle(Theme.secondary)
                        }
                    } else {
                        Picker("Voice", selection: $voiceID) {
                            Text("Best available").tag("")
                            ForEach(voices, id: \.identifier) { v in
                                Text(label(for: v)).tag(v.identifier)
                            }
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
                    Text("Premium and Enhanced voices are neural, free and work offline. Download more in Settings, Accessibility, Spoken Content, Voices.")
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
                    Toggle("HUD upside down", isOn: $flipped)
                } header: {
                    Text("Display")
                } footer: {
                    Text("Lay the phone flat on the dashboard, screen up, with mirroring on. Turn mirroring off to read the HUD directly. Upside down turns the whole HUD 180° so the phone can lie with its charger end toward you.")
                }
                Section("About") {
                    Text("Lane guidance, road names and speed limits use OpenStreetMap data where it has been mapped. © OpenStreetMap contributors.")
                        .font(.footnote)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { voices = Voice.naturalVoices() }   // pick up a voice downloaded in Settings
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
