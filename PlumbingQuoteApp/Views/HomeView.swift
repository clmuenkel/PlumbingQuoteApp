import SwiftUI
import UIKit

struct HomeView: View {
    private enum Field {
        case name
        case phone
        case address
        case notes
    }

    @StateObject private var viewModel = QuoteViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showingMenu = false
    @State private var showClearConfirm = false
    @State private var animateRecordingPulse = false
    @State private var showRecordingSaved = false
    @State private var isKeyboardVisible = false
    @State private var easterEggTapCount = 0
    @State private var lastEasterEggTapAt = Date.distantPast
    @State private var showDuckEasterEgg = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: contentSpacing) {
                    if !networkMonitor.isConnected {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.exclamationmark")
                            Text("Offline mode: reconnect to generate quotes.")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(AppTheme.warning.opacity(0.14))
                        .foregroundStyle(AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    MultiImagePicker(images: $viewModel.capturedImages, maxImages: 5)
                    if !viewModel.capturedImages.isEmpty {
                        Text("\(viewModel.capturedImages.count)/5 photos")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    customerInfoSection

                    voiceSection

                    if let error = viewModel.error {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(error)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(AppTheme.error)

                            if viewModel.canSubmit, !viewModel.isAnalyzing {
                                Button {
                                    viewModel.retryQuoteGeneration()
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(10)
                        .background(AppTheme.error.opacity(0.11))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 4)
                    }
                }
                .padding(contentPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.bg)
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardVisible {
                    actionArea
                        .padding(.horizontal, contentPadding)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(AppTheme.bgAlt)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(AppTheme.accentLight.opacity(0.45))
                                .frame(height: 1)
                        }
                }
            }
            .navigationTitle("PlumbQuote")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppTheme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarColorScheme(.light, for: .bottomBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingMenu = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.headline)
                            .frame(width: menuButtonSize, height: menuButtonSize)
                            .background(AppTheme.surface2)
                            .foregroundStyle(AppTheme.text)
                            .clipShape(Circle())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.canSubmit {
                        Button("Clear") {
                            showClearConfirm = true
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .sheet(isPresented: $showingMenu) {
                MenuView()
            }
            .confirmationDialog(
                "Clear everything? Photos, voice notes, and customer info will be removed.",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    viewModel.clearInputs()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Input quality warning",
                isPresented: $viewModel.showOverridePrompt,
                titleVisibility: .visible
            ) {
                Button("Generate Anyway", role: .destructive) {
                    viewModel.startGenerateQuote(forceOverride: true)
                }
                Button("Improve Input", role: .cancel) {
                    viewModel.showOverridePrompt = false
                }
            } message: {
                if viewModel.overridePromptReasons.isEmpty {
                    Text("Input may be too weak for a reliable quote.")
                } else {
                    Text("• " + viewModel.overridePromptReasons.joined(separator: "\n• "))
                }
            }
            .fullScreenCover(isPresented: $viewModel.showQuoteResult) {
                if let result = viewModel.quoteResult {
                    QuoteResultView(
                        result: result,
                        selectedTier: $viewModel.selectedTier,
                        onDismiss: { viewModel.showQuoteResult = false },
                        onQuoteSaved: { tier, updatedQuote in
                            viewModel.quoteResult?.updateQuote(updatedQuote, for: tier)
                        }
                    )
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 150, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleTitleTapEasterEgg()
                    }
                    .padding(.top, 2)
            }
            .overlay(alignment: .topTrailing) {
                if showDuckEasterEgg {
                    Text("🦆")
                        .font(.system(size: 36))
                        .padding(.trailing, 18)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let developerAlert = viewModel.developerAlert {
                    VStack(spacing: 4) {
                        Text(developerAlert.title)
                            .font(.caption.weight(.semibold))
                        Text(developerAlert.message)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.warning.opacity(0.95))
                    .foregroundStyle(AppTheme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
            .overlay(alignment: .bottom) {
                if showRecordingSaved {
                    Text("Recording saved")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.success.opacity(0.95))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 88)
                }
            }
            .onChange(of: viewModel.developerAlert?.id) { _ in
                guard viewModel.developerAlert != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    viewModel.developerAlert = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
        }
    }

    private var actionArea: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.startGenerateQuote(forceOverride: false)
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isAnalyzing {
                        ProgressView().tint(.white)
                    }
                    Text(viewModel.isAnalyzing ? "Generating Quote" : "Generate Quote")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: primaryButtonHeight)
                .background(viewModel.canSubmit ? AppTheme.accent : AppTheme.muted.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!viewModel.canSubmit || viewModel.isAnalyzing)

            if viewModel.isAnalyzing {
                if !viewModel.generationStep.isEmpty {
                    Text(viewModel.generationStep)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }
                Button("Cancel") {
                    viewModel.cancelQuoteGeneration()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.error)
            }
        }
    }

    @ViewBuilder
    private var voiceSection: some View {
        VStack(spacing: 14) {
            Button {
                viewModel.voiceService.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .stroke(AppTheme.accentLight.opacity(0.8), lineWidth: 2)
                        .frame(width: recordButtonDiameter + 20, height: recordButtonDiameter + 20)
                        .scaleEffect(viewModel.voiceService.isRecording && animateRecordingPulse ? 1.08 : 0.9)
                        .opacity(viewModel.voiceService.isRecording ? (animateRecordingPulse ? 0.15 : 0.5) : 0)
                        .animation(
                            viewModel.voiceService.isRecording
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .easeInOut(duration: 0.2),
                            value: animateRecordingPulse
                        )

                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: recordButtonDiameter, height: recordButtonDiameter)

                    Image(systemName: viewModel.voiceService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: recordButtonIconSize, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .onChange(of: viewModel.voiceService.isRecording) { isRecording in
                if isRecording {
                    animateRecordingPulse = true
                } else {
                    animateRecordingPulse = false
                    if viewModel.voiceService.hasTranscript {
                        showRecordingSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            showRecordingSaved = false
                        }
                    }
                }
            }

            Text(voiceStatusText)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)

            waveformBars

            if viewModel.voiceService.isRecording {
                Text("\(formattedRecordingTime) remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recordingRingColor)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.voiceService.recordingSecondsRemaining)
            }

            if !viewModel.voiceService.isAuthorized {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label("Enable Speech Recognition in Settings", systemImage: "gear")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            }

            if viewModel.voiceService.hasTranscript {
                Text(viewModel.voiceService.transcript)
                    .font(.callout)
                    .foregroundStyle(AppTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                voiceActionButtons
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private var waveformBars: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                let offset = (Float(index) - 2) * 0.06
                let normalized = max(0.08, min(1, viewModel.voiceService.audioLevel + offset))
                RoundedRectangle(cornerRadius: 3)
                    .fill(recordingRingColor.opacity(0.9))
                    .frame(width: 6, height: 8 + CGFloat(normalized) * 24)
            }
        }
        .padding(.vertical, 2)
        .animation(.easeInOut(duration: 0.12), value: viewModel.voiceService.audioLevel)
        .accessibilityHidden(true)
    }

    private var voiceStatusText: String {
        if viewModel.voiceService.isRecording { return "Recording... Tap again to stop" }
        if viewModel.voiceService.hasTranscript { return "Tap to continue recording (new audio appends)" }
        return "Tap to record voice note"
    }

    @ViewBuilder
    private var voiceActionButtons: some View {
        if isCompactWidth || dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                playbackButton
                rerecordButton
            }
        } else {
            HStack(spacing: 12) {
                playbackButton
                rerecordButton
            }
        }
    }

    private var playbackButton: some View {
        Button {
            if viewModel.voiceService.isPlaying {
                viewModel.voiceService.stopPlayback()
            } else {
                viewModel.voiceService.playback()
            }
        } label: {
            Label(
                viewModel.voiceService.isPlaying ? "Stop Playback" : "Play Recording",
                systemImage: viewModel.voiceService.isPlaying ? "stop.circle.fill" : "play.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 42)
            .background(AppTheme.surface2)
            .foregroundStyle(AppTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var rerecordButton: some View {
        Button {
            viewModel.voiceService.clearTranscript()
        } label: {
            Label("Re-record", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 42)
                .background(AppTheme.surface2)
                .foregroundStyle(AppTheme.text)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var customerInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.text.rectangle")
                Text("Job Details")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 2)

            HStack(spacing: 10) {
                Image(systemName: "person")
                    .foregroundStyle(AppTheme.muted)
                TextField("Customer name", text: $viewModel.customerName)
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(AppTheme.text)
                    .focused($focusedField, equals: .name)
            }
            .padding(10)
            .background(AppTheme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Image(systemName: "phone")
                    .foregroundStyle(AppTheme.muted)
                TextField("Phone", text: formattedPhoneBinding)
                    .keyboardType(.phonePad)
                    .foregroundStyle(AppTheme.text)
                    .focused($focusedField, equals: .phone)
            }
            .padding(10)
            .background(AppTheme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Image(systemName: "map")
                    .foregroundStyle(AppTheme.muted)
                TextField("Address", text: $viewModel.customerAddress)
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(AppTheme.text)
                    .focused($focusedField, equals: .address)
            }
            .padding(10)
            .background(AppTheme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.additionalNotes)
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(AppTheme.text)
                    .focused($focusedField, equals: .notes)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)

                if viewModel.additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Any extra details about the job...")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .background(AppTheme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private var formattedPhoneBinding: Binding<String> {
        Binding(
            get: { formatPhone(viewModel.customerPhone) },
            set: { viewModel.customerPhone = sanitizePhone($0) }
        )
    }

    private func sanitizePhone(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(10))
    }

    private func formatPhone(_ value: String) -> String {
        let digits = sanitizePhone(value)
        switch digits.count {
        case 0...3:
            return digits
        case 4...6:
            let area = digits.prefix(3)
            let rest = digits.dropFirst(3)
            return "(\(area)) \(rest)"
        default:
            let area = digits.prefix(3)
            let mid = digits.dropFirst(3).prefix(3)
            let end = digits.dropFirst(6)
            return "(\(area)) \(mid)-\(end)"
        }
    }

    private var recordingRingColor: Color {
        let seconds = viewModel.voiceService.recordingSecondsRemaining
        if seconds <= 5 { return AppTheme.error }
        if seconds <= 10 { return AppTheme.warning }
        return viewModel.voiceService.isRecording ? AppTheme.accent : AppTheme.muted
    }

    private var formattedRecordingTime: String {
        let total = max(0, viewModel.voiceService.recordingSecondsRemaining)
        return "0:\(String(format: "%02d", total))"
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var contentSpacing: CGFloat {
        16
    }

    private var contentPadding: CGFloat {
        isCompactWidth ? 16 : 20
    }

    private var menuButtonSize: CGFloat {
        36
    }

    private var recordButtonDiameter: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 80 : 72
    }

    private var recordButtonIconSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 30 : 26
    }

    private var primaryButtonHeight: CGFloat {
        50
    }

    private func handleTitleTapEasterEgg() {
        let now = Date()
        if now.timeIntervalSince(lastEasterEggTapAt) > 2 {
            easterEggTapCount = 0
        }

        easterEggTapCount += 1
        lastEasterEggTapAt = now

        guard easterEggTapCount >= 5 else { return }
        easterEggTapCount = 0

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            showDuckEasterEgg = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.25)) {
                showDuckEasterEgg = false
            }
        }
    }
}

#Preview {
    HomeView()
}
