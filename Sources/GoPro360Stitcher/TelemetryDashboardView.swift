import SwiftUI

struct TelemetryDashboardView: View {
    @ObservedObject var telemetry: TelemetryProcessor
    var showSpeed: Bool = true
    var showAltitude: Bool = true
    var showGForce: Bool = true
    
    var body: some View {
        HStack(spacing: 16) {
            if showSpeed {
                TelemetryGauge(title: "SPEED", value: telemetry.currentSpeed, unit: "km/h", maxValue: 200)
            }
            if showAltitude {
                TelemetryGauge(title: "ALTITUDE", value: telemetry.currentAltitude, unit: "m", maxValue: 3000)
            }
            if showGForce {
                GForceBubble(
                    lateral: telemetry.currentGForceLateral,
                    longitudinal: telemetry.currentGForceLongitudinal,
                    vertical: telemetry.currentGForceVertical
                )
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 10)
    }
}

// MARK: - G-Force Bubble (Motorsport-style crosshair)

struct GForceBubble: View {
    let lateral: Double
    let longitudinal: Double
    let vertical: Double
    
    private let maxG: Double = 3.0
    private let bubbleSize: CGFloat = 80
    
    /// Normalized position of the G dot within the bubble area
    private var dotOffset: CGSize {
        let clampedLat = max(-maxG, min(maxG, lateral))
        let clampedLong = max(-maxG, min(maxG, longitudinal))
        let halfSize = bubbleSize / 2.0
        let x = CGFloat(clampedLat / maxG) * halfSize
        let y = CGFloat(-clampedLong / maxG) * halfSize // Invert: forward = up
        return CGSize(width: x, height: y)
    }
    
    /// Color intensity based on total G magnitude
    private var dotColor: Color {
        let totalG = sqrt(lateral * lateral + longitudinal * longitudinal)
        if totalG > 2.0 { return .red }
        if totalG > 1.0 { return .orange }
        return .green
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("G-FORCE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .kerning(1)
            
            ZStack {
                // Background circles (G rings)
                ForEach([1.0, 2.0, 3.0], id: \.self) { ring in
                    Circle()
                        .stroke(Color.white.opacity(ring == 1.0 ? 0.15 : 0.07), lineWidth: 0.5)
                        .frame(width: bubbleSize * CGFloat(ring / maxG),
                               height: bubbleSize * CGFloat(ring / maxG))
                }
                
                // Crosshair lines
                Path { p in
                    p.move(to: CGPoint(x: 0, y: bubbleSize / 2))
                    p.addLine(to: CGPoint(x: bubbleSize, y: bubbleSize / 2))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                
                Path { p in
                    p.move(to: CGPoint(x: bubbleSize / 2, y: 0))
                    p.addLine(to: CGPoint(x: bubbleSize / 2, y: bubbleSize))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                
                // G-force dot with trail
                Circle()
                    .fill(dotColor.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .offset(dotOffset)
                
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: dotColor.opacity(0.6), radius: 4)
                    .offset(dotOffset)
                    .animation(.linear(duration: 0.1), value: dotOffset.width)
                    .animation(.linear(duration: 0.1), value: dotOffset.height)
                
                // Axis labels
                Text("F")
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .offset(y: -(bubbleSize / 2) - 6)
                
                Text("B")
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .offset(y: (bubbleSize / 2) + 6)
                
                Text("L")
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .offset(x: -(bubbleSize / 2) - 6)
                
                Text("R")
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .offset(x: (bubbleSize / 2) + 6)
            }
            .frame(width: bubbleSize + 16, height: bubbleSize + 16)
            
            // Numeric readout
            HStack(spacing: 8) {
                GAxisLabel(axis: "LAT", value: lateral, color: .cyan)
                GAxisLabel(axis: "LON", value: longitudinal, color: .orange)
                GAxisLabel(axis: "VRT", value: vertical, color: .purple)
            }
        }
    }
}

struct GAxisLabel: View {
    let axis: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: -1) {
            Text(axis)
                .font(.system(size: 6, weight: .bold, design: .rounded))
                .foregroundColor(color.opacity(0.7))
            Text(String(format: "%.1f", value))
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

struct TelemetryGauge: View {
    let title: String
    let value: Double
    let unit: String
    let maxValue: Double
    
    var progress: Double {
        max(0, min(abs(value) / maxValue, 1.0))
    }
    
    var gaugeColor: Color {
        if title == "SPEED" {
            return value > 100 ? .red : (value > 50 ? .orange : .blue)
        } else {
            return .cyan
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .kerning(1)
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
                
                Circle()
                    .trim(from: 0.0, to: progress)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progress)
                
                VStack(spacing: -2) {
                    Text(String(format: "%.1f", abs(value)))
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .foregroundColor(.white)
                    
                    Text(unit)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(width: 50, height: 50)
        }
    }
}
