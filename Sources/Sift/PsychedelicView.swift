import SwiftUI

enum PsychedelicEffect: Int, CaseIterable {
    case waves, plasma, aurora, starfield, matrix
    case tunnel, spirograph, lightning, crt, vortex
    case confetti, gridFloor, phyllotaxis, pixelSort, fireflies
    case sunburst, ekg, bouncingBalls, sonar, hexCells

    var key: String {
        switch self {
        case .waves: return "waves"
        case .plasma: return "plasma"
        case .aurora: return "aurora"
        case .starfield: return "starfield"
        case .matrix: return "matrix"
        case .tunnel: return "tunnel"
        case .spirograph: return "spirograph"
        case .lightning: return "lightning"
        case .crt: return "crt"
        case .vortex: return "vortex"
        case .confetti: return "confetti"
        case .gridFloor: return "gridFloor"
        case .phyllotaxis: return "phyllotaxis"
        case .pixelSort: return "pixelSort"
        case .fireflies: return "fireflies"
        case .sunburst: return "sunburst"
        case .ekg: return "ekg"
        case .bouncingBalls: return "bouncingBalls"
        case .sonar: return "sonar"
        case .hexCells: return "hexCells"
        }
    }

    var displayName: String {
        switch self {
        case .waves: return "Waves"
        case .plasma: return "Plasma"
        case .aurora: return "Aurora"
        case .starfield: return "Starfield"
        case .matrix: return "Matrix"
        case .tunnel: return "Tunnel"
        case .spirograph: return "Spirograph"
        case .lightning: return "Lightning"
        case .crt: return "CRT"
        case .vortex: return "Vortex"
        case .confetti: return "Confetti"
        case .gridFloor: return "Grid floor"
        case .phyllotaxis: return "Phyllotaxis"
        case .pixelSort: return "Pixel sort"
        case .fireflies: return "Fireflies"
        case .sunburst: return "Sunburst"
        case .ekg: return "EKG"
        case .bouncingBalls: return "Bouncing balls"
        case .sonar: return "Sonar"
        case .hexCells: return "Hex cells"
        }
    }

    static func random() -> PsychedelicEffect {
        allCases.randomElement() ?? .waves
    }

    static func random(excluding disabled: Set<String>) -> PsychedelicEffect? {
        let pool = allCases.filter { !disabled.contains($0.key) }
        return pool.randomElement()
    }
}

struct PsychedelicView: View {
    let intensity: Double
    let effect: PsychedelicEffect

    init(intensity: Double, effect: PsychedelicEffect = .random()) {
        self.intensity = intensity
        self.effect = effect
    }

    var body: some View {
        Group {
            if intensity < 0.05 {
                Color.clear
            } else {
                Group {
                    switch effect {
                    case .waves: WavesEffect(intensity: intensity)
                    case .plasma: PlasmaEffect(intensity: intensity)
                    case .aurora: AuroraEffect(intensity: intensity)
                    case .starfield: StarfieldEffect(intensity: intensity)
                    case .matrix: MatrixEffect(intensity: intensity)
                    case .tunnel: TunnelEffect(intensity: intensity)
                    case .spirograph: SpirographEffect(intensity: intensity)
                    case .lightning: LightningEffect(intensity: intensity)
                    case .crt: CRTEffect(intensity: intensity)
                    case .vortex: VortexEffect(intensity: intensity)
                    case .confetti: ConfettiEffect(intensity: intensity)
                    case .gridFloor: GridFloorEffect(intensity: intensity)
                    case .phyllotaxis: PhyllotaxisEffect(intensity: intensity)
                    case .pixelSort: PixelSortEffect(intensity: intensity)
                    case .fireflies: FirefliesEffect(intensity: intensity)
                    case .sunburst: SunburstEffect(intensity: intensity)
                    case .ekg: EKGEffect(intensity: intensity)
                    case .bouncingBalls: BouncingBallsEffect(intensity: intensity)
                    case .sonar: SonarEffect(intensity: intensity)
                    case .hexCells: HexCellsEffect(intensity: intensity)
                    }
                }
                .opacity(intensity)
            }
        }
        .allowsHitTesting(false)
    }
}

@ViewBuilder
private func psychedelicCanvas<Content: View>(
    intensity: Double,
    @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content
) -> some View {
    if intensity >= 0.5 {
        TimelineView(.animation) { ctx in content(ctx) }
    } else {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { ctx in content(ctx) }
    }
}

private struct WavesEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                ZStack {
                    Color.black.opacity(0.30)
                    Canvas { c, _ in
                        let count = 14
                        for i in 0..<count {
                            var path = Path()
                            let baseY = (Double(i) + 0.5) / Double(count) * size.height
                            let phase = t * (0.35 + Double(i % 4) * 0.18) + Double(i) * 0.55
                            let amp = size.height * (0.035 + Double(i % 3) * 0.012)
                            let freq = 1.1 + Double(i % 5) * 0.27
                            let steps = 160
                            for s in 0...steps {
                                let u = Double(s) / Double(steps)
                                let x = size.width * u
                                let theta = u * freq * 2 * .pi + phase
                                let y = baseY + sin(theta) * amp + sin(theta * 0.5 + phase * 0.7) * amp * 0.4
                                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            let hue = ((Double(i) / Double(count)) + t * 0.07).truncatingRemainder(dividingBy: 1)
                            c.stroke(path,
                                     with: .color(Color(hue: hue, saturation: 0.92, brightness: 1.0).opacity(0.85)),
                                     style: StrokeStyle(lineWidth: 1.4 + Double(i % 3) * 0.8, lineCap: .round))
                        }
                    }
                    .blendMode(.plusLighter)

                    Canvas { c, _ in
                        let count = 22
                        for i in 0..<count {
                            var path = Path()
                            let baseX = (Double(i) + 0.5) / Double(count) * size.width
                            let phase = t * 0.28 + Double(i) * 0.35
                            let amp = 14.0 + Double(i % 4) * 6
                            let steps = 80
                            for s in 0...steps {
                                let u = Double(s) / Double(steps)
                                let y = size.height * u
                                let x = baseX + sin(u * 3 * .pi + phase) * amp + sin(u * 7 * .pi - phase * 0.5) * amp * 0.4
                                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            let hue = ((Double(i) / Double(count)) * 0.7 + 0.3 + t * 0.05).truncatingRemainder(dividingBy: 1)
                            c.stroke(path,
                                     with: .color(Color(hue: hue, saturation: 0.8, brightness: 1.0).opacity(0.4)),
                                     style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .blur(radius: 2)
                .saturation(1.35)
                .drawingGroup()
            }
        }
    }
}

private struct PlasmaEffect: View {
    private struct Blob {
        let color: Color
        let seed: Double
        let radius: CGFloat
        let ax: CGFloat
        let ay: CGFloat
        let fx: Double
        let fy: Double
    }

    private static let blobs: [Blob] = [
        Blob(color: Color(red: 1.00, green: 0.18, blue: 0.62), seed: 0.0, radius: 0.55, ax: 0.42, ay: 0.30, fx: 0.07, fy: 0.05),
        Blob(color: Color(red: 0.20, green: 0.95, blue: 1.00), seed: 1.3, radius: 0.62, ax: 0.36, ay: 0.40, fx: 0.06, fy: 0.09),
        Blob(color: Color(red: 0.62, green: 0.30, blue: 1.00), seed: 2.6, radius: 0.58, ax: 0.45, ay: 0.34, fx: 0.05, fy: 0.07),
        Blob(color: Color(red: 0.65, green: 1.00, blue: 0.30), seed: 3.9, radius: 0.50, ax: 0.40, ay: 0.42, fx: 0.08, fy: 0.06),
        Blob(color: Color(red: 1.00, green: 0.55, blue: 0.10), seed: 5.2, radius: 0.54, ax: 0.38, ay: 0.36, fx: 0.04, fy: 0.10),
        Blob(color: Color(red: 0.10, green: 0.45, blue: 1.00), seed: 6.5, radius: 0.60, ax: 0.44, ay: 0.32, fx: 0.09, fy: 0.04)
    ]

    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let minDim = min(size.width, size.height)
                ZStack {
                    Color.black.opacity(0.45)
                    ForEach(Self.blobs.indices, id: \.self) { i in
                        let b = Self.blobs[i]
                        let cx = size.width / 2 + sin(t * b.fx * 2 * .pi + b.seed) * b.ax * size.width
                        let cy = size.height / 2 + cos(t * b.fy * 2 * .pi + b.seed * 1.3) * b.ay * size.height
                        let pulse = 0.85 + 0.15 * sin(t * 0.6 + b.seed)
                        let r = b.radius * minDim * pulse
                        Circle()
                            .fill(RadialGradient(
                                colors: [b.color.opacity(0.95), b.color.opacity(0.45), b.color.opacity(0)],
                                center: .center, startRadius: 0, endRadius: r))
                            .frame(width: r * 2, height: r * 2)
                            .position(x: cx, y: cy)
                            .blendMode(.plusLighter)
                    }
                }
                .blur(radius: 70)
                .hueRotation(.degrees(sin(t * 0.12) * 40))
                .saturation(1.25)
                .drawingGroup()
            }
        }
    }
}

private struct AuroraEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                ZStack {
                    Color.black.opacity(0.55)
                    Canvas { c, _ in
                        let ribbons = 7
                        for i in 0..<ribbons {
                            let baseX = (Double(i) + 0.5) / Double(ribbons) * size.width
                            let phase = t * (0.22 + Double(i) * 0.05) + Double(i) * 1.1
                            var path = Path()
                            let steps = 90
                            for s in 0...steps {
                                let u = Double(s) / Double(steps)
                                let y = u * size.height
                                let xOff = sin(u * 1.5 * .pi + phase) * 90 + sin(u * 4 * .pi + phase * 0.7) * 22
                                let x = baseX + xOff
                                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            let hue = ((Double(i) / Double(ribbons)) * 0.45 + 0.35 + t * 0.04).truncatingRemainder(dividingBy: 1)
                            let color = Color(hue: hue, saturation: 0.85, brightness: 1.0)
                            c.stroke(path,
                                     with: .color(color.opacity(0.55)),
                                     style: StrokeStyle(lineWidth: 70, lineCap: .round))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .blur(radius: 32)
                .saturation(1.25)
                .drawingGroup()
            }
        }
    }
}

private struct StarfieldEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                ZStack {
                    Color.black.opacity(0.7)
                    Canvas { c, _ in
                        let cx = size.width / 2
                        let cy = size.height / 2
                        let maxR = hypot(size.width, size.height) / 2
                        let starCount = 240
                        var rng = SeededRNG(seed: 17)
                        for _ in 0..<starCount {
                            let angle = rng.nextUnit() * 2 * .pi
                            let lifeOffset = rng.nextUnit()
                            let speed = 0.18 + rng.nextUnit() * 0.22
                            let depth = (t * speed + lifeOffset).truncatingRemainder(dividingBy: 1)
                            let r = depth * maxR * 1.25
                            let prevR = max(0, r - 30 * depth - 4)
                            let x1 = cx + cos(angle) * r
                            let y1 = cy + sin(angle) * r
                            let x0 = cx + cos(angle) * prevR
                            let y0 = cy + sin(angle) * prevR
                            let hue = ((angle / (2 * .pi)) + t * 0.05).truncatingRemainder(dividingBy: 1)
                            let alpha = min(1, depth * 1.6)
                            var path = Path()
                            path.move(to: CGPoint(x: x0, y: y0))
                            path.addLine(to: CGPoint(x: x1, y: y1))
                            c.stroke(path,
                                     with: .color(Color(hue: hue, saturation: 0.9, brightness: 1.0).opacity(alpha)),
                                     style: StrokeStyle(lineWidth: 0.9 + depth * 1.6, lineCap: .round))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .saturation(1.2)
                .drawingGroup()
            }
        }
    }
}

private struct MatrixEffect: View {
    private static let glyphs: [String] = ["0","1","Ϟ","ψ","Δ","∞","Ξ","λ","Ω","φ","§","◊","◉","#","@","✦","✺","∴","≡","◈"]

    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let colWidth = 20.0
                let colCount = max(1, Int(size.width / colWidth))
                let rowHeight = 22.0

                ZStack {
                    Color.black.opacity(0.78)
                    Canvas { c, _ in
                        for col in 0..<colCount {
                            var rng = SeededRNG(seed: UInt64(col) &* 17 &+ 7)
                            let speed = 60 + rng.nextUnit() * 140
                            let phase = rng.nextUnit() * 100
                            let headY = ((t * speed + phase).truncatingRemainder(dividingBy: size.height + 400)) - 200
                            let length = 16 + Int(rng.nextUnit() * 16)
                            let baseHue = rng.nextUnit()
                            for i in 0..<length {
                                let y = headY - Double(i) * rowHeight
                                if y < -rowHeight || y > size.height { continue }
                                let alpha = 1 - Double(i) / Double(length)
                                let glyphIdx = Int((t * 5 + Double(col) * 3 + Double(i) * 7)
                                    .truncatingRemainder(dividingBy: Double(Self.glyphs.count)))
                                let glyph = Self.glyphs[abs(glyphIdx) % Self.glyphs.count]
                                let isHead = i == 0
                                let hue = (baseHue + t * 0.06).truncatingRemainder(dividingBy: 1)
                                let color = isHead ? Color.white : Color(hue: hue, saturation: 0.85, brightness: 1.0)
                                let text = Text(glyph)
                                    .font(.system(size: isHead ? 16 : 14, weight: isHead ? .bold : .regular, design: .monospaced))
                                    .foregroundStyle(color.opacity(alpha))
                                c.draw(text, at: CGPoint(x: Double(col) * colWidth + colWidth / 2, y: y))
                            }
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .saturation(1.2)
            }
        }
    }
}

private struct TunnelEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let cx = size.width / 2
                let cy = size.height / 2
                let maxR = hypot(size.width, size.height) / 2
                let rings = 24
                let sides = 7

                ZStack {
                    Color.black.opacity(0.55)
                    Canvas { c, _ in
                        for r in 0..<rings {
                            let progress = (t * 0.22 + Double(r) / Double(rings)).truncatingRemainder(dividingBy: 1)
                            let radius = progress * maxR * 1.2
                            if radius < 6 { continue }
                            var path = Path()
                            for s in 0...sides {
                                let theta = Double(s) / Double(sides) * 2 * .pi + t * 0.3 + Double(r) * 0.18
                                let x = cx + cos(theta) * radius
                                let y = cy + sin(theta) * radius
                                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            path.closeSubpath()
                            let hue = (progress + t * 0.1).truncatingRemainder(dividingBy: 1)
                            let alpha = 1 - progress
                            let color = Color(hue: hue, saturation: 0.9, brightness: 1.0).opacity(alpha * 0.95)
                            c.stroke(path, with: .color(color), lineWidth: 1.5 + progress * 3)
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .saturation(1.3)
                .drawingGroup()
            }
        }
    }
}

private struct SpirographEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let cx = size.width / 2
                let cy = size.height / 2
                let baseR = min(size.width, size.height) * 0.36

                ZStack {
                    Color.black.opacity(0.55)
                    Canvas { c, _ in
                        let curves = 4
                        for cIdx in 0..<curves {
                            let R = baseR * (1.0 - Double(cIdx) * 0.13)
                            let r = R * (0.30 + 0.18 * sin(t * 0.07 + Double(cIdx)))
                            let d = R * (0.40 + 0.22 * sin(t * 0.05 + Double(cIdx) * 1.3))
                            let steps = 700
                            var path = Path()
                            let phase = t * 0.4 + Double(cIdx) * .pi / 2
                            for s in 0...steps {
                                let theta = Double(s) / Double(steps) * 22 * .pi + phase
                                let x = cx + (R - r) * cos(theta) + d * cos((R - r) / r * theta)
                                let y = cy + (R - r) * sin(theta) - d * sin((R - r) / r * theta)
                                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            let hue = (Double(cIdx) * 0.27 + t * 0.06).truncatingRemainder(dividingBy: 1)
                            c.stroke(path,
                                     with: .color(Color(hue: hue, saturation: 0.92, brightness: 1.0).opacity(0.75)),
                                     style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .blur(radius: 0.8)
                .saturation(1.4)
                .drawingGroup()
            }
        }
    }
}

private struct LightningEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let boltCount = 4
                let boltPeriod = 0.55

                ZStack {
                    Color.black.opacity(0.7)
                    Canvas { c, _ in
                        for b in 0..<boltCount {
                            let offset = Double(b) * (boltPeriod / Double(boltCount))
                            let elapsed = max(0, t - offset)
                            let cycle = floor(elapsed / boltPeriod)
                            let localT = elapsed - cycle * boltPeriod
                            let life = localT / boltPeriod
                            let boltID = UInt64(bitPattern: Int64(cycle)) &* 31 &+ UInt64(b) &* 7
                            var rng = SeededRNG(seed: boltID)

                            let startEdge = rng.nextUnit()
                            let endEdge = (startEdge + 0.5 + rng.nextUnit() * 0.4).truncatingRemainder(dividingBy: 1)
                            let p0 = pointOnEdge(startEdge, size: size)
                            let p1 = pointOnEdge(endEdge, size: size)

                            let flash = life < 0.08 ? life / 0.08 : max(0, 1 - (life - 0.08) / 0.92)
                            let hue = rng.nextUnit()
                            let color = Color(hue: hue, saturation: 0.5, brightness: 1.0)

                            let path = jaggedPath(from: p0, to: p1, rng: &rng)
                            c.stroke(path, with: .color(color.opacity(flash)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            c.stroke(path, with: .color(.white.opacity(flash * 0.7)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .blur(radius: 0.6)
                .saturation(1.3)
            }
        }
    }

    private func pointOnEdge(_ u: Double, size: CGSize) -> CGPoint {
        let v = u.truncatingRemainder(dividingBy: 1)
        let perim = v * 4
        switch perim {
        case ..<1: return CGPoint(x: size.width * perim, y: 0)
        case ..<2: return CGPoint(x: size.width, y: size.height * (perim - 1))
        case ..<3: return CGPoint(x: size.width * (3 - perim), y: size.height)
        default: return CGPoint(x: 0, y: size.height * (4 - perim))
        }
    }

    private func jaggedPath(from a: CGPoint, to b: CGPoint, rng: inout SeededRNG) -> Path {
        var path = Path()
        path.move(to: a)
        let segments = 28
        let dx = (b.x - a.x) / Double(segments)
        let dy = (b.y - a.y) / Double(segments)
        let perpX = -dy
        let perpY = dx
        let len = max(0.01, hypot(perpX, perpY))
        let nx = perpX / len
        let ny = perpY / len
        for i in 1...segments {
            let baseX = a.x + dx * Double(i)
            let baseY = a.y + dy * Double(i)
            let taper = 1 - abs(Double(i) / Double(segments) - 0.5) * 2
            let jitter = (rng.nextUnit() - 0.5) * 70 * taper
            path.addLine(to: CGPoint(x: baseX + nx * jitter, y: baseY + ny * jitter))
        }
        return path
    }
}

private struct CRTEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size

                ZStack {
                    Color.black.opacity(0.8)

                    Canvas { c, _ in
                        let bandCount = 5
                        for i in 0..<bandCount {
                            let phase = t * (0.5 + Double(i) * 0.15)
                            let y = (sin(phase) * 0.5 + 0.5) * size.height
                            let bandHeight = 40 + Double(i) * 12
                            let rect = CGRect(x: 0, y: y - bandHeight / 2, width: size.width, height: bandHeight)
                            let rOffset = sin(t * 3 + Double(i)) * 10
                            let bOffset = -sin(t * 3 + Double(i)) * 10
                            c.fill(Path(rect.offsetBy(dx: rOffset, dy: 0)), with: .color(.red.opacity(0.32)))
                            c.fill(Path(rect), with: .color(.green.opacity(0.32)))
                            c.fill(Path(rect.offsetBy(dx: bOffset, dy: 0)), with: .color(.blue.opacity(0.32)))
                        }
                    }
                    .blendMode(.plusLighter)

                    Canvas { c, _ in
                        let barY = (t * 90).truncatingRemainder(dividingBy: size.height + 80) - 40
                        c.fill(Path(CGRect(x: 0, y: barY, width: size.width, height: 32)),
                               with: .color(.white.opacity(0.18)))
                        c.fill(Path(CGRect(x: 0, y: barY + 32, width: size.width, height: 2)),
                               with: .color(.cyan.opacity(0.7)))
                        c.fill(Path(CGRect(x: 0, y: barY - 2, width: size.width, height: 2)),
                               with: .color(.pink.opacity(0.5)))
                    }
                    .blendMode(.plusLighter)

                    Canvas { c, _ in
                        var y: CGFloat = 0
                        while y < size.height {
                            c.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                   with: .color(.black.opacity(0.45)))
                            y += 3
                        }
                    }

                    Canvas { c, _ in
                        var rng = SeededRNG(seed: UInt64(t * 40))
                        let count = Int(size.width * size.height / 700)
                        for _ in 0..<count {
                            let x = rng.nextUnit() * size.width
                            let y = rng.nextUnit() * size.height
                            let s = rng.nextUnit() * 1.8 + 0.4
                            c.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                                   with: .color(.white.opacity(rng.nextUnit() * 0.55)))
                        }
                    }
                    .blendMode(.plusLighter)
                    .opacity(0.55)
                }
                .saturation(1.15)
            }
        }
    }
}

private struct VortexEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let cx = size.width / 2
                let cy = size.height / 2
                let maxR = hypot(size.width, size.height) / 2

                ZStack {
                    Color.black.opacity(0.55)
                    Canvas { c, _ in
                        let armCount = 6
                        for arm in 0..<armCount {
                            var path = Path()
                            let armPhase = Double(arm) * 2 * .pi / Double(armCount) + t * 0.4
                            let steps = 220
                            for s in 0...steps {
                                let u = Double(s) / Double(steps)
                                let r = u * maxR * 1.2
                                let theta = armPhase + u * 6 * .pi
                                let x = cx + cos(theta) * r
                                let y = cy + sin(theta) * r
                                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            let hue = (Double(arm) / Double(armCount) + t * 0.05).truncatingRemainder(dividingBy: 1)
                            c.stroke(path,
                                     with: .color(Color(hue: hue, saturation: 0.9, brightness: 1.0).opacity(0.75)),
                                     style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        }

                        let dotCount = 70
                        for d in 0..<dotCount {
                            var rng = SeededRNG(seed: UInt64(d) &* 11 &+ 3)
                            let armIdx = Int(rng.nextUnit() * Double(6))
                            let armPhase = Double(armIdx) * 2 * .pi / 6 + t * 0.4
                            let speed = 0.08 + rng.nextUnit() * 0.08
                            let offset = rng.nextUnit()
                            let u = (t * speed + offset).truncatingRemainder(dividingBy: 1)
                            let r = u * maxR * 1.2
                            let theta = armPhase + u * 6 * .pi
                            let x = cx + cos(theta) * r
                            let y = cy + sin(theta) * r
                            let hue = ((Double(armIdx) / 6.0) + t * 0.05).truncatingRemainder(dividingBy: 1)
                            let sz = 3 + u * 4
                            c.fill(Path(ellipseIn: CGRect(x: x - sz/2, y: y - sz/2, width: sz, height: sz)),
                                   with: .color(Color(hue: hue, saturation: 0.7, brightness: 1.0).opacity(u)))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .blur(radius: 1.2)
                .saturation(1.35)
                .drawingGroup()
            }
        }
    }
}

private struct ConfettiEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                ZStack {
                    Color.black.opacity(0.65)
                    Canvas { c, _ in
                        let count = 180
                        for i in 0..<count {
                            var rng = SeededRNG(seed: UInt64(i) &* 23 &+ 5)
                            let xBase = rng.nextUnit() * size.width
                            let speed = 50 + rng.nextUnit() * 110
                            let phase = rng.nextUnit() * 1000
                            let yPos = ((t * speed + phase).truncatingRemainder(dividingBy: size.height + 60)) - 30
                            let swing = sin(t * 1.5 + Double(i)) * 40
                            let x = xBase + swing
                            let rotation = t * (1.5 + rng.nextUnit() * 2) + rng.nextUnit() * .pi
                            let hue = rng.nextUnit()
                            let color = Color(hue: hue, saturation: 0.9, brightness: 1.0)
                            let w = 6 + rng.nextUnit() * 4
                            let h = 10 + rng.nextUnit() * 6
                            let basePath = Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                            let transform = CGAffineTransform(rotationAngle: rotation)
                                .concatenating(CGAffineTransform(translationX: x, y: yPos))
                            c.fill(basePath.applying(transform), with: .color(color.opacity(0.88)))
                        }
                    }
                }
                .saturation(1.2)
                .drawingGroup()
            }
        }
    }
}

private struct GridFloorEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let horizon = size.height * 0.5
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.02, blue: 0.18), Color.black],
                        startPoint: .top, endPoint: .bottom
                    )
                    Canvas { c, _ in
                        let lineCount = 22
                        let scroll = t * 0.4
                        for i in 0..<lineCount {
                            let progress = (Double(i) / Double(lineCount) + scroll).truncatingRemainder(dividingBy: 1)
                            let z = pow(progress, 2)
                            let y = horizon + z * (size.height - horizon)
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            c.stroke(path, with: .color(Color.cyan.opacity(z * 0.95)), lineWidth: 1)
                        }
                        let vCount = 18
                        let cx = size.width / 2
                        for v in 0..<vCount {
                            let u = Double(v) - Double(vCount) / 2
                            let near = cx + u * (size.width / Double(vCount)) * 1.6
                            var path = Path()
                            path.move(to: CGPoint(x: cx, y: horizon))
                            path.addLine(to: CGPoint(x: near, y: size.height))
                            let hue = ((Double(v) / Double(vCount)) + t * 0.05).truncatingRemainder(dividingBy: 1)
                            c.stroke(path,
                                     with: .color(Color(hue: hue, saturation: 0.85, brightness: 1.0).opacity(0.75)),
                                     lineWidth: 1.5)
                        }
                    }
                    .blendMode(.plusLighter)

                    let sunR = size.height * 0.16
                    Circle()
                        .fill(RadialGradient(
                            colors: [
                                Color(red: 1, green: 0.4, blue: 0.6),
                                Color(red: 1, green: 0.6, blue: 0.2),
                                Color(red: 0.5, green: 0.15, blue: 0.3),
                                Color.black
                            ],
                            center: .center, startRadius: 0, endRadius: sunR
                        ))
                        .frame(width: sunR * 2, height: sunR * 2)
                        .position(x: size.width / 2, y: horizon - sunR * 0.45)
                        .blendMode(.plusLighter)
                }
                .saturation(1.2)
                .drawingGroup()
            }
        }
    }
}

private struct PhyllotaxisEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let cx = size.width / 2
                let cy = size.height / 2
                let goldenAngle = .pi * (3 - sqrt(5.0))
                let scale = min(size.width, size.height) * 0.036
                ZStack {
                    Color.black.opacity(0.55)
                    Canvas { c, _ in
                        let n = 380
                        let breath = 0.85 + 0.18 * sin(t * 0.45)
                        for i in 0..<n {
                            let a = Double(i) * goldenAngle + t * 0.22
                            let r = sqrt(Double(i)) * scale * breath
                            let x = cx + cos(a) * r
                            let y = cy + sin(a) * r
                            let hue = (Double(i) / Double(n) + t * 0.05).truncatingRemainder(dividingBy: 1)
                            let sz = 2.5 + sin(t + Double(i) * 0.08) * 1.2
                            c.fill(Path(ellipseIn: CGRect(x: x - sz/2, y: y - sz/2, width: sz, height: sz)),
                                   with: .color(Color(hue: hue, saturation: 0.85, brightness: 1.0).opacity(0.9)))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .saturation(1.3)
                .drawingGroup()
            }
        }
    }
}

private struct PixelSortEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                ZStack {
                    Color.black.opacity(0.5)
                    Canvas { c, _ in
                        let bandCount = 42
                        let bandH = size.height / Double(bandCount)
                        for i in 0..<bandCount {
                            var rng = SeededRNG(seed: UInt64(i) &* 31 &+ 11)
                            let baseHue = rng.nextUnit()
                            let speed = 30 + rng.nextUnit() * 90
                            let direction: Double = i.isMultiple(of: 2) ? 1 : -1
                            let offset = (t * speed * direction).truncatingRemainder(dividingBy: size.width)
                            let stripes = 14
                            for s in 0..<stripes {
                                let stripeW = size.width / Double(stripes)
                                let raw = Double(s) * stripeW + offset
                                let x = raw.truncatingRemainder(dividingBy: size.width + stripeW) - stripeW
                                let hue = (baseHue + Double(s) * 0.06 + t * 0.02).truncatingRemainder(dividingBy: 1)
                                let color = Color(hue: hue, saturation: 0.85, brightness: 1.0)
                                let rect = CGRect(x: x, y: Double(i) * bandH, width: stripeW, height: bandH)
                                c.fill(Path(rect), with: .color(color.opacity(0.75)))
                            }
                        }
                    }
                }
                .saturation(1.2)
                .drawingGroup()
            }
        }
    }
}

private struct FirefliesEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                ZStack {
                    Color.black.opacity(0.78)
                    Canvas { c, _ in
                        let count = 120
                        for i in 0..<count {
                            var rng = SeededRNG(seed: UInt64(i) &* 19 &+ 7)
                            let speed = 0.25 + rng.nextUnit() * 0.45
                            let phaseX = rng.nextUnit() * 100
                            let phaseY = rng.nextUnit() * 100
                            let driftRangeX = 0.15 + rng.nextUnit() * 0.35
                            let driftRangeY = 0.15 + rng.nextUnit() * 0.35
                            let x = (sin(t * speed + phaseX) * driftRangeX + 0.5) * size.width
                            let y = (cos(t * speed * 0.73 + phaseY) * driftRangeY + 0.5) * size.height
                            let blinkSpeed = 1.0 + rng.nextUnit() * 2
                            let blink = max(0, sin(t * blinkSpeed + phaseX) * 0.5 + 0.5)
                            let hue = 0.13 + rng.nextUnit() * 0.08
                            let color = Color(hue: hue, saturation: 0.7, brightness: 1.0)
                            let sz = 3 + blink * 5
                            c.fill(Path(ellipseIn: CGRect(x: x - sz, y: y - sz, width: sz * 2, height: sz * 2)),
                                   with: .color(color.opacity(blink * 0.45)))
                            c.fill(Path(ellipseIn: CGRect(x: x - sz/2, y: y - sz/2, width: sz, height: sz)),
                                   with: .color(color.opacity(blink)))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .blur(radius: 2)
                .saturation(1.2)
                .drawingGroup()
            }
        }
    }
}

private struct SunburstEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let cx = size.width / 2
                let cy = size.height / 2
                let maxR = hypot(size.width, size.height)
                ZStack {
                    Color.black.opacity(0.55)
                    Canvas { c, _ in
                        let rays = 64
                        let pulse = 0.7 + 0.3 * sin(t * 1.4)
                        for i in 0..<rays {
                            let angle = Double(i) / Double(rays) * 2 * .pi + t * 0.3
                            let length = maxR * pulse * (0.55 + 0.45 * sin(t * 0.5 + Double(i) * 0.22))
                            var path = Path()
                            path.move(to: CGPoint(x: cx, y: cy))
                            path.addLine(to: CGPoint(x: cx + cos(angle) * length, y: cy + sin(angle) * length))
                            let hue = (Double(i) / Double(rays) + t * 0.1).truncatingRemainder(dividingBy: 1)
                            c.stroke(path,
                                     with: .color(Color(hue: hue, saturation: 0.9, brightness: 1.0).opacity(0.55)),
                                     lineWidth: 2)
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .blur(radius: 1)
                .saturation(1.3)
                .drawingGroup()
            }
        }
    }
}

private struct EKGEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                ZStack {
                    Color.black.opacity(0.72)
                    Canvas { c, _ in
                        let lines = 7
                        for i in 0..<lines {
                            let baseY = (Double(i) + 0.5) / Double(lines) * size.height
                            let speed = 90 + Double(i) * 22
                            let beatOffset = Double(i) * 0.22
                            var path = Path()
                            let stride = 3
                            let steps = Int(size.width) / stride
                            for s in 0...steps {
                                let x = Double(s * stride)
                                let timeAtX = t - (Double(steps - s) * Double(stride) / speed)
                                let beat = Self.ekgPulse(time: timeAtX + beatOffset)
                                let y = baseY - beat * 70
                                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            let hue = (Double(i) / Double(lines) + t * 0.04).truncatingRemainder(dividingBy: 1)
                            c.stroke(path,
                                     with: .color(Color(hue: hue, saturation: 0.9, brightness: 1.0).opacity(0.9)),
                                     style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .saturation(1.2)
                .drawingGroup()
            }
        }
    }

    private static func ekgPulse(time t: Double) -> Double {
        let period = 0.95
        var p = t.truncatingRemainder(dividingBy: period) / period
        if p < 0 { p += 1 }
        if p < 0.1 { return sin(p * .pi / 0.1) * 0.18 }
        if p < 0.2 { return -sin((p - 0.1) * .pi / 0.1) * 0.32 }
        if p < 0.3 { return sin((p - 0.2) * .pi / 0.1) * 1.0 }
        if p < 0.45 { return -sin((p - 0.3) * .pi / 0.15) * 0.14 }
        return 0
    }
}

private struct BouncingBallsEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                ZStack {
                    Color.black.opacity(0.55)
                    Canvas { c, _ in
                        let ballCount = 24
                        for i in 0..<ballCount {
                            var rng = SeededRNG(seed: UInt64(i) &* 41 &+ 3)
                            let vx = (rng.nextUnit() - 0.5) * 320
                            let vy = (rng.nextUnit() - 0.5) * 320
                            let r = 12 + rng.nextUnit() * 18
                            let hue = rng.nextUnit()
                            let color = Color(hue: hue, saturation: 0.85, brightness: 1.0)
                            let phase = rng.nextUnit() * 100
                            for trail in 0..<7 {
                                let dt = Double(trail) * 0.04
                                let tx = Self.bouncingPos((t - dt) * vx + phase, range: size.width - 2 * r) + r
                                let ty = Self.bouncingPos((t - dt) * vy + phase * 1.3, range: size.height - 2 * r) + r
                                let alpha = (1 - Double(trail) / 7) * 0.35
                                let rr = r * (1 - Double(trail) / 9)
                                c.fill(Path(ellipseIn: CGRect(x: tx - rr, y: ty - rr, width: rr * 2, height: rr * 2)),
                                       with: .color(color.opacity(alpha)))
                            }
                            let x = Self.bouncingPos(t * vx + phase, range: size.width - 2 * r) + r
                            let y = Self.bouncingPos(t * vy + phase * 1.3, range: size.height - 2 * r) + r
                            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                   with: .color(color.opacity(0.9)))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .blur(radius: 1.6)
                .saturation(1.25)
                .drawingGroup()
            }
        }
    }

    private static func bouncingPos(_ x: Double, range: Double) -> Double {
        guard range > 0 else { return 0 }
        let mod = x.truncatingRemainder(dividingBy: range * 2)
        let pos = mod < 0 ? mod + range * 2 : mod
        return pos < range ? pos : range * 2 - pos
    }
}

private struct SonarEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                ZStack {
                    Color.black.opacity(0.7)
                    Canvas { c, _ in
                        let pings = 6
                        let period = 2.5
                        for p in 0..<pings {
                            let offset = Double(p) * (period / Double(pings))
                            let elapsed = max(0, t - offset)
                            let cycle = floor(elapsed / period)
                            let localT = elapsed - cycle * period
                            let life = localT / period
                            let pingID = UInt64(bitPattern: Int64(cycle)) &* 17 &+ UInt64(p) &* 5 &+ 13
                            var rng = SeededRNG(seed: pingID)
                            let cx = rng.nextUnit() * size.width
                            let cy = rng.nextUnit() * size.height
                            let maxR = min(size.width, size.height) * 0.45
                            let hue = rng.nextUnit()
                            let color = Color(hue: hue, saturation: 0.85, brightness: 1.0)
                            for ring in 0..<3 {
                                let ringLife = life - Double(ring) * 0.18
                                if ringLife < 0 || ringLife > 1 { continue }
                                let radius = ringLife * maxR
                                let alpha = (1 - ringLife) * 0.9
                                let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                                c.stroke(Path(ellipseIn: rect), with: .color(color.opacity(alpha)), lineWidth: 1.5)
                            }
                            c.fill(Path(ellipseIn: CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8)),
                                   with: .color(color.opacity((1 - life) * 0.85)))
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .blur(radius: 0.5)
                .saturation(1.2)
                .drawingGroup()
            }
        }
    }
}

private struct HexCellsEffect: View {
    let intensity: Double
    var body: some View {
        psychedelicCanvas(intensity: intensity) { ctx in
            GeometryReader { proxy in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let cellSize = 36.0
                let hSpacing = cellSize * sqrt(3.0)
                let vSpacing = cellSize * 1.5
                let cols = Int(size.width / hSpacing) + 2
                let rows = Int(size.height / vSpacing) + 2
                ZStack {
                    Color.black.opacity(0.65)
                    Canvas { c, _ in
                        for r in 0..<rows {
                            for col in 0..<cols {
                                let xOff = (r % 2 == 0 ? 0 : hSpacing / 2)
                                let cx = Double(col) * hSpacing + xOff - hSpacing / 2
                                let cy = Double(r) * vSpacing - vSpacing / 2
                                let wave = sin(t * 0.85 + Double(col + r) * 0.32 + sin(Double(col - r) * 0.4) * 0.6)
                                let activity = (wave + 1) / 2
                                guard activity > 0.42 else { continue }
                                var path = Path()
                                for i in 0..<6 {
                                    let theta = Double(i) * .pi / 3 + .pi / 6
                                    let x = cx + cos(theta) * cellSize * 0.85
                                    let y = cy + sin(theta) * cellSize * 0.85
                                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                                }
                                path.closeSubpath()
                                let hue = (Double(col) * 0.05 + Double(r) * 0.07 + t * 0.07).truncatingRemainder(dividingBy: 1)
                                let color = Color(hue: hue, saturation: 0.85, brightness: 1.0)
                                c.fill(path, with: .color(color.opacity((activity - 0.42) * 1.2)))
                                c.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1)
                            }
                        }
                    }
                    .blendMode(.plusLighter)
                }
                .saturation(1.25)
                .drawingGroup()
            }
        }
    }
}

private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
