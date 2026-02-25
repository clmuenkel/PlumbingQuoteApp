import SwiftUI
import UIKit

struct MultiImagePicker: View {
    @Binding var images: [UIImage]
    let maxImages: Int

    @State private var showSourcePicker = false
    @State private var showImagePicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    @State private var pendingImage: UIImage?
    @State private var previewImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
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
                            .frame(width: 90, height: 90)
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
        .sheet(isPresented: $showImagePicker, onDismiss: appendPendingImageIfNeeded) {
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
        self.pendingImage = nil
    }
}
