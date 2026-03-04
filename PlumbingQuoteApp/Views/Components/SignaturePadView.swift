import SwiftUI
import UIKit

struct SignaturePadView: View {
    let onCancel: () -> Void
    let onDone: (UIImage) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Customer Signature")
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)

                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.accentLight.opacity(0.8), lineWidth: 1)
                            )

                        Canvas { context, size in
                            var path = Path()
                            for stroke in strokes {
                                addStroke(stroke, to: &path)
                            }
                            addStroke(currentStroke, to: &path)
                            context.stroke(path, with: .color(.black), lineWidth: 2.0)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                currentStroke.append(value.location)
                            }
                            .onEnded { _ in
                                if !currentStroke.isEmpty {
                                    strokes.append(currentStroke)
                                }
                                currentStroke = []
                            }
                    )
                    .onAppear {
                        canvasSize = geo.size
                        if geo.size.width < 1 || geo.size.height < 1 {
                            strokes = []
                            currentStroke = []
                        }
                    }
                }
                .frame(minHeight: signatureCanvasHeight)

                HStack {
                    Button("Clear") {
                        strokes.removeAll()
                        currentStroke.removeAll()
                    }
                    .foregroundStyle(AppTheme.error)

                    Spacer()

                    Button("Done") {
                        guard let image = renderSignatureImage(size: CGSize(width: 900, height: 400)) else { return }
                        onDone(image)
                    }
                    .fontWeight(.semibold)
                    .disabled(strokes.isEmpty && currentStroke.isEmpty)
                }
            }
            .padding()
            .background(AppTheme.bgAlt)
            .toolbarBackground(AppTheme.bgAlt, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }

    private func addStroke(_ points: [CGPoint], to path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
    }

    private func renderSignatureImage(size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor.black.setStroke()
            let bezier = UIBezierPath()
            bezier.lineWidth = 3
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                bezier.move(to: scaled(first, in: size))
                for point in stroke.dropFirst() {
                    bezier.addLine(to: scaled(point, in: size))
                }
            }
            bezier.stroke()
        }
    }

    private func scaled(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return point }
        return CGPoint(
            x: point.x * (size.width / canvasSize.width),
            y: point.y * (size.height / canvasSize.height)
        )
    }

    private var signatureCanvasHeight: CGFloat {
        horizontalSizeClass == .compact ? 260 : 320
    }
}
