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
    // Per-axis G-force from IMU accelerometer
    let gForceLateral: Double   // X — side-to-side (cornering)
    let gForceLongitudinal: Double // Z — front-to-back (braking/accel)
    let gForceVertical: Double  // Y — up-down (bumps/jumps)
}

class TelemetryProcessor: ObservableObject {
    @Published var trackPoints: [GPSPoint] = []
    
    // Dynamic overlay data
    @Published var currentSpeed: Double = 0.0 // km/h
    @Published var currentAltitude: Double = 0.0 // meters
    @Published var currentGForceLateral: Double = 0.0 // Gs — cornering
    @Published var currentGForceLongitudinal: Double = 0.0 // Gs — braking/accel
    @Published var currentGForceVertical: Double = 0.0 // Gs — bumps
    
    // Normalized track bounds for drawing
    private(set) var minLat: Double = 0
    private(set) var maxLat: Double = 0
    private(set) var minLon: Double = 0
    private(set) var maxLon: Double = 0
    
    @MainActor
    func loadTelemetry(_ rawData: [GPSData]) {
        print("🛰 [Telemetry] Processing \(rawData.count) native GPS data points...")
        var newPoints: [GPSPoint] = []
        
        for data in rawData {
            let time = data.timestamp.seconds
            
            // Convert raw m/s² to G-force (1G = 9.80665 m/s²)
            // GoPro MAX axes: X=lateral, Y=vertical (-9.8 at rest), Z=longitudinal
            let gLat = data.accelX / 9.80665
            let gVert = data.accelY / 9.80665
            let gLong = data.accelZ / 9.80665
            
            let point = GPSPoint(
                latitude: data.coordinate.latitude,
                longitude: data.coordinate.longitude,
                altitude: data.altitude,
                speed: data.speed,
                speed3D: data.speed3D,
                timestamp: time,
                gForceLateral: gLat,
                gForceLongitudinal: gLong,
                gForceVertical: gVert
            )
            
            newPoints.append(point)
        }
        
        // Smooth G-Force arrays (moving average) to reduce IMU noise/jitter
        let window = 5
        var smoothedPoints = newPoints
        for i in 0..<newPoints.count {
            let start = max(0, i - window)
            let end = min(newPoints.count - 1, i + window)
            let slice = newPoints[start...end]
            let avgLat = slice.map { $0.gForceLateral }.reduce(0, +) / Double(slice.count)
            let avgLong = slice.map { $0.gForceLongitudinal }.reduce(0, +) / Double(slice.count)
            let avgVert = slice.map { $0.gForceVertical }.reduce(0, +) / Double(slice.count)
            
            smoothedPoints[i] = GPSPoint(
                id: newPoints[i].id,
                latitude: newPoints[i].latitude,
                longitude: newPoints[i].longitude,
                altitude: newPoints[i].altitude,
                speed: newPoints[i].speed,
                speed3D: newPoints[i].speed3D,
                timestamp: newPoints[i].timestamp,
                gForceLateral: avgLat,
                gForceLongitudinal: avgLong,
                gForceVertical: avgVert
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
            self.currentGForceLateral = currentPoint.gForceLateral
            self.currentGForceLongitudinal = currentPoint.gForceLongitudinal
            self.currentGForceVertical = currentPoint.gForceVertical
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
