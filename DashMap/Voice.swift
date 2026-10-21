import AVFoundation
import DashMapCore

final class Voice {
    static let voiceKey = "voice.id"
    static let rateKey = "voice.rate"
    static let defaultRate = Double(AVSpeechUtteranceDefaultSpeechRate)

    private let synth = AVSpeechSynthesizer()
    var enabled = true

    /// Voices installed for the device language, best quality first.
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(lang) }
            .sorted {
                $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality.rawValue : $0.name < $1.name
            }
    }

    private var chosenVoice: AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: Voice.voiceKey), let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        // No choice made: use the most natural installed voice (Premium, then Enhanced) over the robotic default.
        return Voice.availableVoices().first ?? AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
    }

    private var chosenRate: Float {
        Float(UserDefaults.standard.object(forKey: Voice.rateKey) as? Double ?? Voice.defaultRate)
    }

    /// Plays a sample with the saved settings, even when guidance is switched off.
    func preview() {
        speak("In 500 feet, turn right onto Main Street.", force: true)
    }

    func speak(_ announcement: Announcement, units: Units, exit: String? = nil) {
        var text: String
        switch announcement.stage {
        case .arrive: text = "You have arrived at your destination."
        case .near: text = announcement.instruction
        case .far: text = "In \(units.distance(announcement.distance)), \(announcement.instruction)"
        }
        if let exit, announcement.stage != .arrive { text += ". \(exit)" }
        if let then = announcement.then { text += ", then \(then)" }
        speak(text)
    }

    func speak(_ text: String, force: Bool = false) {
        guard enabled || force else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        synth.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = chosenVoice
        utterance.rate = chosenRate
        synth.speak(utterance)
    }
}
