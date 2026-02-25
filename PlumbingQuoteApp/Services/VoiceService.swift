import Foundation
import Speech
import AVFoundation

// MARK: - Voice Service (Speech-to-Text)
class VoiceService: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var isAuthorized: Bool = false
    @Published var error: String?
    @Published var recordingSecondsRemaining: Int = 55
    
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var initialTranscript: String = ""
    private var countdownTimer: Timer?
    
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
        // Reset
        recognitionTask?.cancel()
        recognitionTask = nil
        initialTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
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
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
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
        
        DispatchQueue.main.async {
            self.isRecording = false
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
}
