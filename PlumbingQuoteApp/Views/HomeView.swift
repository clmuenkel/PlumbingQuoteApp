import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = QuoteViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showingMenu = false
    @State private var isPressingMic = false
    @State private var showCustomerInfo = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                topBar

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if viewModel.canSubmit, !viewModel.isAnalyzing {
                            Button("Retry") {
                                viewModel.retryQuoteGeneration()
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }

                Spacer()

                Button {
                    viewModel.startGenerateQuote()
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isAnalyzing {
                            ProgressView().tint(.white)
                        }
                        Text(viewModel.isAnalyzing ? "Generating..." : "Generate Quote")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(viewModel.canSubmit ? Color.blue : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!viewModel.canSubmit || viewModel.isAnalyzing)

                if viewModel.isAnalyzing {
                    Button("Cancel") {
                        viewModel.cancelQuoteGeneration()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                }
            }
            .padding(18)
            .background(Color(.systemBackground))
            .sheet(isPresented: $showingMenu) {
                MenuView()
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
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                showingMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.headline)
                    .frame(width: 32, height: 32)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }

            Spacer()

            if viewModel.canSubmit {
                Button("Clear") {
                    viewModel.clearInputs()
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    private var voiceSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(viewModel.voiceService.isRecording ? Color.red.opacity(0.18) : Color.blue.opacity(0.15))
                    .frame(width: 110, height: 110)
                    .overlay(
                        Circle()
                            .stroke(recordingRingColor, lineWidth: viewModel.voiceService.isRecording ? 4 : 1)
                    )

                Image(systemName: viewModel.voiceService.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(viewModel.voiceService.isRecording ? .red : .blue)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressingMic else { return }
                        isPressingMic = true
                        if !viewModel.voiceService.isRecording {
                            viewModel.voiceService.startRecording()
                        }
                    }
                    .onEnded { _ in
                        isPressingMic = false
                        if viewModel.voiceService.isRecording {
                            viewModel.voiceService.stopRecording()
                        }
                    }
            )

            Text(viewModel.voiceService.isRecording ? "Release to stop recording" : "Hold to record voice description")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
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
}

#Preview {
    HomeView()
}
