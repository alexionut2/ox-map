import AVFoundation
import Observation
import OxydeCore

/// Speaks guidance with AVSpeechSynthesizer. The audio session uses the voice-prompt
/// mode so CarPlay and the car's audio system treat it as navigation audio, ducking or
/// pausing other audio per the user's settings.
@MainActor
@Observable
final class VoiceGuidanceManager: NSObject, AVSpeechSynthesizerDelegate {
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    private(set) var isInterrupted = false
    @ObservationIgnored var settings = VoiceSettings()

    override init() {
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            Task { @MainActor in
                // A phone call or Siri takes the audio; guidance resumes with the next prompt.
                self?.isInterrupted = type == .began
                if type == .began { self?.synthesizer.stopSpeaking(at: .immediate) }
            }
        }
    }

    /// Installed voices for a language, best quality first.
    static func voices(for language: String?) -> [AVSpeechSynthesisVoice] {
        let lang = language ?? AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String(lang.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { ($0.quality.rawValue, $0.language == lang ? 1 : 0) > ($1.quality.rawValue, $1.language == lang ? 1 : 0) }
    }

    static var availableLanguages: [String] {
        Array(Set(AVSpeechSynthesisVoice.speechVoices().map(\.language))).sorted()
    }

    func speak(_ announcement: Announcement) {
        guard settings.guidanceLevel != .muted, !isInterrupted else { return }
        if announcement.interrupts, synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
        speak(text: announcement.text)
    }

    /// Plays a sample in Voice settings.
    func preview(_ text: String) { speak(text: text) }

    private func speak(text: String) {
        activateSession()
        let u = AVSpeechUtterance(string: text)
        if let id = settings.voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            u.voice = v
        } else {
            u.voice = Self.voices(for: settings.language).first ?? AVSpeechSynthesisVoice(language: settings.language)
        }
        u.volume = Float(settings.volume)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * Float(settings.rate)
        u.prefersAssistiveTechnologySettings = true
        synthesizer.speak(u)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
    }

    private func activateSession() {
        var options: AVAudioSession.CategoryOptions = []
        if settings.duckOtherAudio { options.insert(.duckOthers) }
        if settings.pauseSpokenAudio { options.insert(.interruptSpokenAudioAndMixWithOthers) }
        if options.isEmpty { options.insert(.mixWithOthers) }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: options)
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            if !self.synthesizer.isSpeaking { self.deactivateSession() }
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

extension GuidancePhrasebook {
    /// Localized templates from Localizable.strings; English is the fallback.
    static var localized: GuidancePhrasebook {
        let inFormat = NSLocalizedString("guidance.in", value: "In %1$@, %2$@", comment: "In <distance>, <instruction>")
        let thenFormat = NSLocalizedString("guidance.then", value: "%1$@, then %2$@", comment: "<instruction>, then <instruction>")
        let rerouted = NSLocalizedString("guidance.rerouted", value: "Route updated.", comment: "Spoken after a reroute")
        let stopFormat = NSLocalizedString("guidance.stop", value: "You have reached %@.", comment: "Arrived at a stop")
        let english = Locale.current.language.languageCode?.identifier == "en"
        return GuidancePhrasebook(
            inDistance: { d, i in String(format: inFormat, d, english ? GuidancePhrasebook.lowercasingFirst(i) : i) },
            then: { a, b in String(format: thenFormat, a, english ? GuidancePhrasebook.lowercasingFirst(b) : b) },
            rerouted: rerouted,
            arrivedAtStop: { String(format: stopFormat, $0) })
    }
}
