import Foundation
import Speech
import AVFoundation

// MARK: - Voice Service (Speech-to-Text)
class VoiceService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var isAuthorized: Bool = false
    @Published var error: String?
    @Published var recordingSecondsRemaining: Int = 55
    @Published var audioLevel: Float = 0
    @Published var isPlaying: Bool = false
    @Published var recordingURL: URL?
    
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var initialTranscript: String = ""
    private var countdownTimer: Timer?
    private var audioFile: AVAudioFile?
    private var audioPlayer: AVAudioPlayer?
    
    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        checkAuthorization()
    }
    
    func checkAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.isAuthorized = true
                default:
                    self?.isAuthorized = false
                    self?.error = "Speech recognition not authorized. Please enable in Settings."
                }
            }
        }
    }
    
    func startRecording() {
        stopPlayback()

        // Reset
        recognitionTask?.cancel()
        recognitionTask = nil
        initialTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
        audioLevel = 0
        resetCountdown()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            self.error = "Unable to create recognition request"
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        
        // On-device recognition if available (faster, works offline)
        if #available(iOS 13, *), speechRecognizer?.supportsOnDeviceRecognition == true {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    let latest = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if self.initialTranscript.isEmpty {
                        self.transcript = latest
                    } else if latest.isEmpty {
                        self.transcript = self.initialTranscript
                    } else {
                        self.transcript = "\(self.initialTranscript)\n\(latest)"
                    }
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    // Don't show error if we just stopped recording
                    if self.isRecording {
                        self.error = error.localizedDescription
                        HapticsService.error()
                    }
                    self.stopRecording()
                }
            }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        do {
            try FileManager.default.removeItem(at: tempRecordingURL)
        } catch {
            // Ignore if file doesn't exist.
        }
        do {
            audioFile = try AVAudioFile(forWriting: tempRecordingURL, settings: recordingFormat.settings)
            recordingURL = nil
        } catch {
            self.error = "Could not prepare audio file: \(error.localizedDescription)"
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            try? self.audioFile?.write(from: buffer)
            let level = self.normalizedRMS(from: buffer)
            DispatchQueue.main.async {
                self.audioLevel = level
            }
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
                HapticsService.recordStarted()
                self.startCountdownTimer()
            }
        } catch {
            self.error = "Audio engine error: \(error.localizedDescription)"
            HapticsService.error()
        }
    }
    
    func stopRecording() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0
            if FileManager.default.fileExists(atPath: self.tempRecordingURL.path) {
                self.recordingURL = self.tempRecordingURL
            }
            self.resetCountdown()
            HapticsService.recordStopped()
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func playback() {
        guard let recordingURL else { return }
        if isRecording {
            stopRecording()
        }
        do {
            try configurePlaybackSessionForSpeaker()
            let player = try AVAudioPlayer(contentsOf: recordingURL)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            isPlaying = true
            player.play()
        } catch {
            self.error = "Playback failed: \(error.localizedDescription)"
            isPlaying = false
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func clearTranscript() {
        stopPlayback()
        transcript = ""
        recordingURL = nil
        audioLevel = 0
        initialTranscript = ""
        error = nil
        try? FileManager.default.removeItem(at: tempRecordingURL)
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.isRecording else { return }
                self.recordingSecondsRemaining -= 1
                if self.recordingSecondsRemaining == 10 {
                    HapticsService.warning()
                }
                if self.recordingSecondsRemaining <= 0 {
                    HapticsService.warning()
                    self.stopRecording()
                }
            }
        }
    }

    private func resetCountdown() {
        recordingSecondsRemaining = 55
    }

    private var tempRecordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("voice_recording.caf")
    }

    private func normalizedRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channel = channelData[0]
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        return min(max(rms * 4.5, 0), 1)
    }

    private func configurePlaybackSessionForSpeaker() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        try audioSession.overrideOutputAudioPort(.speaker)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.audioPlayer = nil
        }
    }
}
