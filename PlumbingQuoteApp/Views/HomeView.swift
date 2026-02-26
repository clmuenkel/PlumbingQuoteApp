import SwiftUI

struct HomeView: View {
    private enum Field {
        case phone
    }

    @StateObject private var viewModel = QuoteViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showingMenu = false
    @State private var showClearConfirm = false
    @State private var showCustomerInfo = false
    @State private var animateRecordingPulse = false
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
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    MultiImagePicker(images: $viewModel.capturedImages, maxImages: 5)

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
                            .foregroundStyle(.red)

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
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 4)
                    }
                }
                .padding(contentPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom) {
                actionArea
                    .padding(.horizontal, contentPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
            }
            .navigationTitle("PlumbQuote")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingMenu = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.headline)
                            .frame(width: menuButtonSize, height: menuButtonSize)
                            .background(Color(.secondarySystemBackground))
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
                        onDismiss: { viewModel.showQuoteResult = false }
                    )
                }
            }
            .alert(
                viewModel.developerAlert?.title ?? "Developer Mode",
                isPresented: Binding(
                    get: { viewModel.developerAlert != nil },
                    set: { showing in
                        if !showing {
                            viewModel.developerAlert = nil
                        }
                    }
                ),
                actions: {
                    Button("OK", role: .cancel) {
                        viewModel.developerAlert = nil
                    }
                },
                message: {
                    Text(viewModel.developerAlert?.message ?? "Unknown developer error.")
                }
            )
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
                .background(viewModel.canSubmit ? Color.blue : Color.gray.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!viewModel.canSubmit || viewModel.isAnalyzing)

            if viewModel.isAnalyzing {
                if !viewModel.generationStep.isEmpty {
                    Text(viewModel.generationStep)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Button("Cancel") {
                    viewModel.cancelQuoteGeneration()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var voiceSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.45), lineWidth: 2)
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
                    .fill(Color.red)
                    .frame(width: recordButtonDiameter, height: recordButtonDiameter)

                Image(systemName: viewModel.voiceService.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: recordButtonIconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .contentShape(Circle())
            .onTapGesture {
                viewModel.voiceService.toggleRecording()
            }
            .onChange(of: viewModel.voiceService.isRecording) { isRecording in
                if isRecording {
                    animateRecordingPulse = true
                } else {
                    animateRecordingPulse = false
                }
            }

            Text(voiceStatusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            waveformBars

            if viewModel.voiceService.isRecording {
                Text("\(formattedRecordingTime) remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recordingRingColor)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.voiceService.recordingSecondsRemaining)
            }

            if viewModel.voiceService.hasTranscript {
                Text(viewModel.voiceService.transcript)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                voiceActionButtons
            }
        }
        .frame(maxWidth: .infinity)
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
        if viewModel.voiceService.hasTranscript { return "Tap to continue recording" }
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
            .background(Color(.secondarySystemBackground))
            .foregroundStyle(.primary)
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
                .background(Color(.secondarySystemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var customerInfoSection: some View {
        DisclosureGroup(isExpanded: $showCustomerInfo) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "person")
                        .foregroundStyle(.secondary)
                    TextField("Customer name", text: $viewModel.customerName)
                        .textInputAutocapitalization(.words)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 10) {
                    Image(systemName: "phone")
                        .foregroundStyle(.secondary)
                    TextField("Phone", text: formattedPhoneBinding)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 10) {
                    Image(systemName: "map")
                        .foregroundStyle(.secondary)
                    TextField("Address", text: $viewModel.customerAddress)
                        .textInputAutocapitalization(.words)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "person.text.rectangle")
                Text("Customer Info")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)
        }
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
        if seconds <= 5 { return .red }
        if seconds <= 10 { return .yellow }
        return viewModel.voiceService.isRecording ? .blue : .secondary
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
}

#Preview {
    HomeView()
}
