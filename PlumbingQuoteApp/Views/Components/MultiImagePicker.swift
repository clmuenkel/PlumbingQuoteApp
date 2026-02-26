import SwiftUI
import UIKit

struct MultiImagePicker: View {
    @Binding var images: [UIImage]
    let maxImages: Int

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showSourcePicker = false
    @State private var showImagePicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    @State private var pendingImage: UIImage?
    @State private var previewImage: UIImage?

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
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: emptyStateHeight)
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                Color.blue.opacity(0.45),
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
                                        previewImage = image
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
                                .background(Color(.secondarySystemBackground))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
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
            get: { previewImage != nil },
            set: { if !$0 { previewImage = nil } }
        )) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                Button {
                    previewImage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .padding()
                }
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
