import SwiftUI

/// A plain-value snapshot of the telemetry at a single point in time.
/// This is safe to pass across concurrency boundaries — no @ObservedObject, no actors.
struct TelemetrySnapshot {
    let speed: Double        // km/h
    let altitude: Double     // m
    let gForceLateral: Double
    let gForceLongitudinal: Double
    let gForceVertical: Double
    let trackPoints: [GPSPoint]
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    let currentTime: Double
    
    static let empty = TelemetrySnapshot(
        speed: 0, altitude: 0,
        gForceLateral: 0, gForceLongitudinal: 0, gForceVertical: 0,
        trackPoints: [], minLat: 0, maxLat: 0, minLon: 0, maxLon: 0,
        currentTime: 0
    )
}

/// An off-screen-safe overlay view that renders telemetry using plain values.
/// Safe to use with ImageRenderer from any thread.
struct ExportOverlaySnapshotView: View {
    let snapshot: TelemetrySnapshot
    let size: CGSize
    let showTrackMap: Bool
    let showDashboard: Bool
    let showSpeed: Bool
    let showAltitude: Bool
    let showGForce: Bool
    let scale: Double

    var body: some View {
        // The UI preview viewport is 9:16 aspect, maxHeight 700pt → ~394 × 700pt.
        // Overlay elements are sized for that ~394pt-wide reference canvas.
        // Scale everything proportionally to the export canvas size.
        let uiReferenceWidth: CGFloat = 9.0 / 16.0 * 700.0  // ≈ 393.75pt — matches ContentView
        let exportScale = size.width / uiReferenceWidth       // e.g. 2160 / 393.75 ≈ 5.49

        ZStack {
            VStack {
                HStack {
                    Spacer()
                    if showTrackMap && !snapshot.trackPoints.isEmpty {
                        // UI uses 100×100pt track map with 10pt outer padding
                        SnapshotTrackMapView(snapshot: snapshot)
                            .frame(width: 100 * exportScale, height: 100 * exportScale)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8 * exportScale))
                            .overlay(RoundedRectangle(cornerRadius: 8 * exportScale)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1 * exportScale))
                    }
                }
                Spacer()
                if showDashboard {
                    HStack {
                        Spacer()
                        SnapshotDashboardView(
                            snapshot: snapshot,
                            showSpeed: showSpeed,
                            showAltitude: showAltitude,
                            showGForce: showGForce
                        )
                        // UI uses .scaleEffect(telemetryScale) on the dashboard
                        .scaleEffect(scale * exportScale, anchor: .bottomTrailing)
                    }
                    .padding(.bottom, 20 * exportScale)
                }
            }
            .padding(10 * exportScale)  // Matches the UI .padding(10)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Snapshot Track Map

struct SnapshotTrackMapView: View {
    let snapshot: TelemetrySnapshot

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let points = snapshot.trackPoints
                guard points.count > 1 else { return }

                for i in 1..<points.count {
                    var path = Path()
                    path.move(to: normalize(points[i - 1], in: size))
                    path.addLine(to: normalize(points[i], in: size))
                    let color = trackColor(for: points[i].speed3D)
                    context.stroke(path, with: .color(color), lineWidth: 2)
                }

                // Current position dot
                if let currentPoint = points.last(where: { $0.timestamp <= snapshot.currentTime }) {
                    let pos = normalize(currentPoint, in: size)
                    let rect = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: rect), with: .color(.red))
                }
            }
        }
        .padding(8)
    }

    private func normalize(_ point: GPSPoint, in size: CGSize) -> CGPoint {
        let latRange = snapshot.maxLat - snapshot.minLat
        let lonRange = snapshot.maxLon - snapshot.minLon
        guard latRange > 0, lonRange > 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let avgLat = (snapshot.maxLat + snapshot.minLat) / 2.0 * .pi / 180.0
        let adjustedLonRange = lonRange * cos(avgLat)
        let scaleX = size.width / adjustedLonRange
        let scaleY = size.height / latRange
        let scale = min(scaleX, scaleY)
        let drawnWidth = adjustedLonRange * scale
        let drawnHeight = latRange * scale
        let offsetX = (size.width - drawnWidth) / 2.0
        let offsetY = (size.height - drawnHeight) / 2.0
        let x = offsetX + ((point.longitude - snapshot.minLon) * cos(avgLat)) * scale
        let y = offsetY + (latRange - (point.latitude - snapshot.minLat)) * scale
        return CGPoint(x: x, y: y)
    }

    private func trackColor(for speed: Double) -> Color {
        let normalized = min(1.0, max(0.0, speed / 30.0))
        return Color(red: normalized, green: 0.2, blue: 1.0 - normalized)
    }
}

// MARK: - Snapshot Dashboard

struct SnapshotDashboardView: View {
    let snapshot: TelemetrySnapshot
    let showSpeed: Bool
    let showAltitude: Bool
    let showGForce: Bool

    var body: some View {
        HStack(spacing: 16) {
            if showSpeed {
                SnapshotGauge(title: "SPEED", value: snapshot.speed, unit: "km/h", maxValue: 200)
            }
            if showAltitude {
                SnapshotGauge(title: "ALTITUDE", value: snapshot.altitude, unit: "m", maxValue: 3000)
            }
            if showGForce {
                SnapshotGForceBubble(
                    lateral: snapshot.gForceLateral,
                    longitudinal: snapshot.gForceLongitudinal,
                    vertical: snapshot.gForceVertical
                )
            }
        }
        .frame(width: 280, height: 150)
        .padding(12)
        // Use solid colour — .ultraThinMaterial is not supported by ImageRenderer
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Snapshot Gauge

struct SnapshotGauge: View {
    let title: String
    let value: Double
    let unit: String
    let maxValue: Double

    var progress: Double { max(0, min(abs(value) / maxValue, 1.0)) }

    var gaugeColor: Color {
        if title == "SPEED" { return value > 100 ? .red : (value > 50 ? .orange : .blue) }
        return .cyan
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .kerning(1)

            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0.0, to: progress)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

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
        .frame(width: 55, height: 75)
    }
}

// MARK: - Snapshot G-Force Bubble

struct SnapshotGForceBubble: View {
    let lateral: Double
    let longitudinal: Double
    let vertical: Double

    private let maxG: Double = 2.0
    private let bubbleSize: CGFloat = 50.0

    private var dotOffset: CGSize {
        let clampedLat = max(-maxG, min(maxG, lateral))
        let clampedLong = max(-maxG, min(maxG, longitudinal))
        let halfSize = bubbleSize / 2.0
        return CGSize(
            width: CGFloat(clampedLat / maxG) * halfSize,
            height: CGFloat(-clampedLong / maxG) * halfSize
        )
    }

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
                .foregroundColor(.white.opacity(0.6))
                .kerning(1)

            ZStack {
                ForEach([1.0, 2.0], id: \.self) { ring in
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        .frame(width: bubbleSize * CGFloat(ring / maxG),
                               height: bubbleSize * CGFloat(ring / maxG))
                }
                Rectangle().fill(Color.white.opacity(0.12))
                    .frame(width: bubbleSize * 1.5, height: 0.5)
                Rectangle().fill(Color.white.opacity(0.12))
                    .frame(width: 0.5, height: bubbleSize * 1.5)

                Circle().fill(dotColor.opacity(0.3))
                    .frame(width: 10, height: 10).offset(dotOffset)
                Circle().fill(dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: dotColor.opacity(0.6), radius: 4)
                    .offset(dotOffset)

                Text("F").font(.system(size: 6, weight: .bold)).foregroundColor(.white.opacity(0.3))
                    .offset(y: -(bubbleSize * 0.75) - 4)
                Text("B").font(.system(size: 6, weight: .bold)).foregroundColor(.white.opacity(0.3))
                    .offset(y: (bubbleSize * 0.75) + 4)
                Text("L").font(.system(size: 6, weight: .bold)).foregroundColor(.white.opacity(0.3))
                    .offset(x: -(bubbleSize * 0.75) - 4)
                Text("R").font(.system(size: 6, weight: .bold)).foregroundColor(.white.opacity(0.3))
                    .offset(x: (bubbleSize * 0.75) + 4)
            }
            .frame(width: bubbleSize * 1.5 + 16, height: bubbleSize * 1.5 + 16)

            HStack(spacing: 8) {
                SnapshotGAxisLabel(axis: "LAT", value: lateral, color: .cyan)
                SnapshotGAxisLabel(axis: "LON", value: longitudinal, color: .orange)
                SnapshotGAxisLabel(axis: "VRT", value: vertical, color: .purple)
            }
        }
        .frame(width: 120, height: 135)
    }
}

struct SnapshotGAxisLabel: View {
    let axis: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: -1) {
            Text(axis)
                .font(.system(size: 6, weight: .bold, design: .rounded))
                .foregroundColor(color.opacity(0.7))
            Text(String(format: "%+.2f", value))
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(width: 32)
    }
}
