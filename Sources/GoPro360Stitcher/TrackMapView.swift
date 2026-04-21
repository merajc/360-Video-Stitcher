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
                    Path { path in
                        let points = telemetry.trackPoints
                        guard let first = points.first else { return }
                        
                        path.move(to: normalize(first, in: geometry.size))
                        for i in 1..<points.count {
                            path.addLine(to: normalize(points[i], in: geometry.size))
                        }
                    }
                    .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                    
                    // Current Position Indicator
                    if let currentPoint = telemetry.trackPoints.last(where: { $0.timestamp <= currentTime }) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .position(normalize(currentPoint, in: geometry.size))
                            .shadow(radius: 2)
                    }
                }
            }
        }
        .padding(8)
    }
    
    private func normalize(_ point: GPSPoint, in size: CGSize) -> CGPoint {
        let latRange = telemetry.maxLat - telemetry.minLat
        let lonRange = telemetry.maxLon - telemetry.minLon
        
        guard latRange > 0, lonRange > 0 else { return CGPoint(x: size.width/2, y: size.height/2) }
        
        let x = (point.longitude - telemetry.minLon) / lonRange * size.width
        let y = (1.0 - (point.latitude - telemetry.minLat) / latRange) * size.height
        
        return CGPoint(x: x, y: y)
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
