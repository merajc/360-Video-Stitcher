import SwiftUI
import CoreLocation

struct TrackMapView: View {
    @ObservedObject var telemetry: TelemetryProcessor
    var currentTime: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZCenter {
                if telemetry.trackPoints.isEmpty {
                    Text("No Telemetry Data")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    let points = telemetry.trackPoints
                    Canvas { context, size in
                        for i in 1..<points.count {
                            var path = Path()
                            path.move(to: normalize(points[i-1], in: size))
                            path.addLine(to: normalize(points[i], in: size))
                            let color = trackColor(for: points[i].speed3D)
                            context.stroke(path, with: .color(color), lineWidth: 2)
                        }
                        
                        // Draw current position indicator
                        if let currentPoint = points.last(where: { $0.timestamp <= currentTime }) {
                            let currentPos = normalize(currentPoint, in: size)
                            let rect = CGRect(x: currentPos.x - 4, y: currentPos.y - 4, width: 8, height: 8)
                            context.fill(Path(ellipseIn: rect), with: .color(.red))
                        }
                    }
                    // Force Canvas invalidation when data or time changes
                    .id("\(points.count)-\(Int(currentTime * 10))")
                }
            }
        }
        .padding(8)
    }
    
    private func normalize(_ point: GPSPoint, in size: CGSize) -> CGPoint {
        let latRange = telemetry.maxLat - telemetry.minLat
        let lonRange = telemetry.maxLon - telemetry.minLon
        
        guard latRange > 0, lonRange > 0 else { return CGPoint(x: size.width/2, y: size.height/2) }
        
        // Latitude adjustment (cos of avg latitude) to approximate square meters
        let avgLat = (telemetry.maxLat + telemetry.minLat) / 2.0 * .pi / 180.0
        let adjustedLonRange = lonRange * cos(avgLat)
        
        let scaleX = size.width / adjustedLonRange
        let scaleY = size.height / latRange
        let scale = min(scaleX, scaleY)
        
        // Calculate the drawn size
        let drawnWidth = adjustedLonRange * scale
        let drawnHeight = latRange * scale
        
        // Offsets to center the map
        let offsetX = (size.width - drawnWidth) / 2.0
        let offsetY = (size.height - drawnHeight) / 2.0
        
        // Standard map orientation: East=right, North=up
        let x = offsetX + ((point.longitude - telemetry.minLon) * cos(avgLat)) * scale
        let y = offsetY + (latRange - (point.latitude - telemetry.minLat)) * scale
        
        return CGPoint(x: x, y: y)
    }
    
    private func trackColor(for speed: Double) -> Color {
        // Assume speed is in m/s. 0 m/s = blue, > 30 m/s (~100km/h) = red
        let normalized = min(1.0, max(0.0, speed / 30.0))
        return Color(red: normalized, green: 0.2, blue: 1.0 - normalized)
    }
}

// Helper for centering
struct ZCenter<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        ZStack {
            content
        }
    }
}
