import AVFoundation
import DashMapCore

final class Voice {
    private let synth = AVSpeechSynthesizer()
    var enabled = true

    func speak(_ announcement: Announcement, units: Units) {
        let text: String
        switch announcement.stage {
        case .arrive: text = "You have arrived at your destination."
        case .near: text = announcement.instruction
        case .far: text = "In \(units.distance(announcement.distance)), \(announcement.instruction)"
        }
        speak(text)
    }

    func speak(_ text: String) {
        guard enabled else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        synth.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
        synth.speak(utterance)
    }
}
