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
                TelemetryGauge(title: "G-FORCE", value: telemetry.currentGForce, unit: "G", maxValue: 3)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 10)
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
        if title == "G-FORCE" {
            return abs(value) > 1.5 ? .red : (abs(value) > 0.8 ? .orange : .green)
        } else if title == "SPEED" {
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
