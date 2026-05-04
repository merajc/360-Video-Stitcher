import Foundation
import CoreLocation
import CoreMedia

struct GPSPoint: Identifiable, Codable {
    var id = UUID()
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let speed3D: Double
    let timestamp: Double // Elapsed time in seconds
    let gForce: Double // Estimated G-force
}

class TelemetryProcessor: ObservableObject {
    @Published var trackPoints: [GPSPoint] = []
    
    // Dynamic overlay data
    @Published var currentSpeed: Double = 0.0 // km/h
    @Published var currentAltitude: Double = 0.0 // meters
    @Published var currentGForce: Double = 0.0 // Gs
    
    // Normalized track bounds for drawing
    private(set) var minLat: Double = 0
    private(set) var maxLat: Double = 0
    private(set) var minLon: Double = 0
    private(set) var maxLon: Double = 0
    
    @MainActor
    func loadTelemetry(_ rawData: [GPSData]) {
        print("🛰 [Telemetry] Processing \(rawData.count) native GPS data points...")
        var newPoints: [GPSPoint] = []
        var previousSpeed: Double = 0.0
        var previousTime: Double = 0.0
        
        for data in rawData {
            let time = data.timestamp.seconds
            
            // Calculate G-Force using derivative of 3D speed (m/s) over time (s)
            // G-force = (deltaV / deltaT) / 9.80665
            var gForce: Double = 0.0
            if time > previousTime {
                let deltaV = data.speed3D - previousSpeed
                let deltaT = time - previousTime
                let acceleration = deltaV / deltaT
                gForce = acceleration / 9.80665
            }
            
            // Clamp gForce to reasonable limits to avoid huge noise spikes
            gForce = max(min(gForce, 5.0), -5.0)
            
            let point = GPSPoint(
                latitude: data.coordinate.latitude,
                longitude: data.coordinate.longitude,
                altitude: data.altitude,
                speed: data.speed,
                speed3D: data.speed3D,
                timestamp: time,
                gForce: gForce
            )
            
            newPoints.append(point)
            
            previousSpeed = data.speed3D
            previousTime = time
        }
        
        // Smooth G-Force array (simple moving average) to reduce jitter
        let window = 5
        var smoothedPoints = newPoints
        for i in 0..<newPoints.count {
            let start = max(0, i - window)
            let end = min(newPoints.count - 1, i + window)
            let slice = newPoints[start...end]
            let avgG = slice.map { $0.gForce }.reduce(0, +) / Double(slice.count)
            
            smoothedPoints[i] = GPSPoint(
                id: newPoints[i].id,
                latitude: newPoints[i].latitude,
                longitude: newPoints[i].longitude,
                altitude: newPoints[i].altitude,
                speed: newPoints[i].speed, // Keep in m/s internally
                speed3D: newPoints[i].speed3D,
                timestamp: newPoints[i].timestamp,
                gForce: avgG
            )
        }
        
        self.trackPoints = smoothedPoints
        self.calculateBounds()
        print("✅ [Telemetry] Ready. Extracted \(smoothedPoints.count) points.")
    }
    
    @MainActor
    func updateCurrentTime(_ time: Double) {
        guard !trackPoints.isEmpty else { return }
        
        // Use the last point where timestamp <= time
        if let currentPoint = trackPoints.last(where: { $0.timestamp <= time }) {
            // Speed in GPMF is m/s. Convert to km/h (m/s * 3.6)
            self.currentSpeed = currentPoint.speed3D * 3.6
            self.currentAltitude = currentPoint.altitude
            self.currentGForce = currentPoint.gForce
        }
    }
    
    private func calculateBounds() {
        guard !trackPoints.isEmpty else { return }
        minLat = trackPoints.map { $0.latitude }.min() ?? 0
        maxLat = trackPoints.map { $0.latitude }.max() ?? 0
        minLon = trackPoints.map { $0.longitude }.min() ?? 0
        maxLon = trackPoints.map { $0.longitude }.max() ?? 0
    }
}
