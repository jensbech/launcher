import SwiftUI
import AppKit

struct MarkupView: View {
    let image: NSImage
    let onCommit: (NSImage) -> Void
    let onCancel: () -> Void

    @State private var strokes: [Stroke] = []
    @State private var currentStroke: Stroke?
    @State private var selectedColor: Color = .red
    @State private var lineWidth: CGFloat = 4

    private static let palette: [Color] = [
        .red,
        Color(red: 1.0, green: 0.78, blue: 0.2),
        Color(red: 0.32, green: 0.85, blue: 0.45),
        Color(red: 0.32, green: 0.65, blue: 1.0),
        .white,
        .black
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geom in
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geom.size.width, height: geom.size.height)
                    Canvas { ctx, _ in
                        for stroke in strokes {
                            drawStroke(stroke, in: ctx)
                        }
                        if let s = currentStroke {
                            drawStroke(s, in: ctx)
                        }
                    }
                    .frame(width: geom.size.width, height: geom.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if currentStroke == nil {
                                    currentStroke = Stroke(points: [value.location], color: selectedColor, width: lineWidth)
                                } else {
                                    currentStroke?.points.append(value.location)
                                }
                            }
                            .onEnded { _ in
                                if let s = currentStroke, !s.points.isEmpty {
                                    strokes.append(s)
                                }
                                currentStroke = nil
                            }
                    )
                }
                .background(Color.black.opacity(0.05))
                .onAppear {
                    self.displayRectSize = geom.size
                }
                .onChange(of: geom.size) { _, newSize in
                    displayRectSize = newSize
                }
            }
        }
    }

    @State private var displayRectSize: CGSize = .zero

    private var toolbar: some View {
        HStack(spacing: 14) {
            ForEach(Self.palette, id: \.self) { color in
                Button {
                    selectedColor = color
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(color == selectedColor ? Color.accentColor : Color.gray.opacity(0.35), lineWidth: color == selectedColor ? 3 : 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Use this color")
            }

            Divider().frame(height: 18)

            Slider(value: $lineWidth, in: 1...12)
                .frame(width: 100)
                .help("Stroke width")

            Spacer()

            Button {
                if !strokes.isEmpty { strokes.removeLast() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(strokes.isEmpty)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo")

            Button {
                strokes.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(strokes.isEmpty)
            .help("Clear annotations")

            Divider().frame(height: 18)

            Button("Cancel", action: cancel)
                .keyboardShortcut(.escape, modifiers: [])

            Button("Copy") { commit() }
                .keyboardShortcut(.return, modifiers: [])
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 50)
    }

    private func drawStroke(_ stroke: Stroke, in ctx: GraphicsContext) {
        guard let first = stroke.points.first else { return }
        var path = Path()
        path.move(to: first)
        for p in stroke.points.dropFirst() {
            path.addLine(to: p)
        }
        ctx.stroke(path,
                   with: .color(stroke.color),
                   style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
    }

    private func commit() {
        let annotated = renderFinalImage()
        onCommit(annotated)
    }

    private func cancel() {
        onCancel()
    }

    private func renderFinalImage() -> NSImage {
        let outputSize = image.size
        let result = NSImage(size: outputSize)
        result.lockFocus()
        defer { result.unlockFocus() }

        image.draw(in: NSRect(origin: .zero, size: outputSize))

        guard let cg = NSGraphicsContext.current?.cgContext else { return result }

        let display = displayRectSize
        let aspectImage = outputSize.width / max(outputSize.height, 1)
        let aspectDisplay = display.width / max(display.height, 1)
        var fitted = CGRect.zero
        if aspectImage > aspectDisplay {
            let h = display.width / aspectImage
            fitted = CGRect(x: 0, y: (display.height - h) / 2, width: display.width, height: h)
        } else {
            let w = display.height * aspectImage
            fitted = CGRect(x: (display.width - w) / 2, y: 0, width: w, height: display.height)
        }
        let scaleX = outputSize.width / max(fitted.width, 1)
        let scaleY = outputSize.height / max(fitted.height, 1)

        cg.saveGState()
        for stroke in strokes {
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setLineWidth(stroke.width * scaleX)
            cg.setStrokeColor(NSColor(stroke.color).cgColor)
            cg.beginPath()
            var first = true
            for p in stroke.points {
                let inFit = CGPoint(x: p.x - fitted.minX, y: p.y - fitted.minY)
                let imgX = inFit.x * scaleX
                let imgY = outputSize.height - inFit.y * scaleY
                if first { cg.move(to: CGPoint(x: imgX, y: imgY)); first = false }
                else { cg.addLine(to: CGPoint(x: imgX, y: imgY)) }
            }
            cg.strokePath()
        }
        cg.restoreGState()
        return result
    }

    struct Stroke {
        var points: [CGPoint]
        var color: Color
        var width: CGFloat
    }
}

