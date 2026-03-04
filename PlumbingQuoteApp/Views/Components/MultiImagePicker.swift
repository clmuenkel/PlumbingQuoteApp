import SwiftUI
import UIKit
import PencilKit

struct MultiImagePicker: View {
    @Binding var images: [UIImage]
    let maxImages: Int

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showSourcePicker = false
    @State private var showImagePicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    @State private var pendingImage: UIImage?
    @State private var annotationIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if images.isEmpty {
                Button {
                    showSourcePicker = true
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: cameraIconSize, weight: .semibold))
                        Text("Add Photos")
                            .font(.headline)
                        Text("Take a photo or choose from library")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: emptyStateHeight)
                    .foregroundStyle(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                AppTheme.accentLight,
                                style: StrokeStyle(lineWidth: 1.5, dash: [8])
                            )
                    )
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: thumbnailSize, height: thumbnailSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .onTapGesture {
                                        annotationIndex = index
                                    }

                                Button {
                                    images.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.headline)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .padding(5)
                            }
                        }

                        if images.count < maxImages {
                            Button {
                                showSourcePicker = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "plus")
                                        .font(.title2.weight(.semibold))
                                    Text("Add")
                                        .font(.caption.weight(.medium))
                                }
                                .frame(width: addTileSize, height: addTileSize)
                                .background(AppTheme.surface2)
                                .foregroundStyle(AppTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(AppTheme.accentLight.opacity(0.5), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .confirmationDialog("Add Photo", isPresented: $showSourcePicker) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    sourceType = .camera
                    showImagePicker = true
                }
            }

            Button("Photo Library") {
                sourceType = .photoLibrary
                showImagePicker = true
            }
        }
        .fullScreenCover(isPresented: $showImagePicker, onDismiss: appendPendingImageIfNeeded) {
            ImagePicker(image: $pendingImage, sourceType: sourceType)
                .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { annotationIndex != nil },
            set: { if !$0 { annotationIndex = nil } }
        )) {
            if let index = annotationIndex, images.indices.contains(index) {
                PhotoAnnotationView(
                    image: images[index],
                    onCancel: { annotationIndex = nil },
                    onSave: { updated in
                        images[index] = updated
                        annotationIndex = nil
                    }
                )
            }
        }
    }

    private func appendPendingImageIfNeeded() {
        guard let pendingImage, images.count < maxImages else { return }
        if let data = pendingImage.compressed(), let compressedImage = UIImage(data: data) {
            images.append(compressedImage)
        } else {
            images.append(pendingImage)
        }
        HapticsService.recordStarted()
        self.pendingImage = nil
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var thumbnailSize: CGFloat {
        isCompactWidth ? 90 : 100
    }

    private var addTileSize: CGFloat {
        thumbnailSize
    }

    private var emptyStateHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 150 : (isCompactWidth ? 120 : 140)
    }

    private var cameraIconSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 30 : (isCompactWidth ? 24 : 26)
    }
}

private struct PhotoAnnotationView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onSave: (UIImage) -> Void

    @State private var drawing = PKDrawing()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                GeometryReader { proxy in
                    let size = fittedSize(in: proxy.size, image: image)
                    let origin = CGPoint(
                        x: (proxy.size.width - size.width) / 2,
                        y: (proxy.size.height - size.height) / 2
                    )
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: size.width, height: size.height)

                        DrawingCanvas(drawing: $drawing)
                            .frame(width: size.width, height: size.height)
                    }
                    .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
                }
            }
            .navigationTitle("Annotate Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(merge(image: image, drawing: drawing))
                    }
                }
            }
        }
    }

    private func fittedSize(in container: CGSize, image: UIImage) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return container }
        let ratio = min(container.width / image.size.width, container.height / image.size.height)
        return CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    }

    private func merge(image: UIImage, drawing: PKDrawing) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            drawing.image(from: CGRect(origin: .zero, size: image.size), scale: image.scale)
                .draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

private struct DrawingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.drawingPolicy = .anyInput
        view.tool = PKInkingTool(.pen, color: .systemRed, width: 5)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawing = drawing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing

        init(drawing: Binding<PKDrawing>) {
            _drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
        }
    }
}
