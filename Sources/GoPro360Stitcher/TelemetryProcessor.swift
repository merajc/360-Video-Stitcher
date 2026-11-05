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
        Log.debug("[Telemetry] Processing \(rawData.count) native GPS data points...")
        var newPoints: [GPSPoint] = []
        
        // Debug: verify incoming accel data
        if let first = rawData.first {
            Log.debug("[Telemetry] First incoming point: accelX=\(String(format: "%.2f", first.accelX)) accelY=\(String(format: "%.2f", first.accelY)) accelZ=\(String(format: "%.2f", first.accelZ)) m/s², ts=\(String(format: "%.3f", first.timestamp.seconds))s")
        }
        
        // Step 1: Detect gravity bias by averaging first 5 seconds of IMU data
        // At low speed, the dominant axis reading is gravity (~9.8 m/s²)
        let biasWindow = rawData.prefix(while: { $0.timestamp.seconds < rawData.first!.timestamp.seconds + 5.0 })
        var biasX = 0.0, biasY = 0.0, biasZ = 0.0
        if !biasWindow.isEmpty {
            biasX = biasWindow.map { $0.accelX }.reduce(0, +) / Double(biasWindow.count)
            biasY = biasWindow.map { $0.accelY }.reduce(0, +) / Double(biasWindow.count)
            biasZ = biasWindow.map { $0.accelZ }.reduce(0, +) / Double(biasWindow.count)
            Log.debug("[Telemetry] Gravity bias (m/s²): X=\(String(format: "%.2f", biasX)) Y=\(String(format: "%.2f", biasY)) Z=\(String(format: "%.2f", biasZ))")
            
            // Identify gravity axis (largest absolute average)
            let absAxes = [abs(biasX), abs(biasY), abs(biasZ)]
            let gravityAxis = absAxes.firstIndex(of: absAxes.max()!)!
            let axisNames = ["X (lateral)", "Y (vertical)", "Z (longitudinal)"]
            Log.debug("[Telemetry] Gravity detected on axis: \(axisNames[gravityAxis]) (\(String(format: "%.1f", absAxes[gravityAxis] / 9.80665))G)")
        }
        
        for data in rawData {
            let time = data.timestamp.seconds
            
            // Subtract gravity bias to get dynamic acceleration only
            let dynX = (data.accelX - biasX) / 9.80665
            let dynY = (data.accelY - biasY) / 9.80665
            let dynZ = (data.accelZ - biasZ) / 9.80665
            
            // GoPro MAX body frame mapping (confirmed by diagnostics):
            // Body X = Vertical (gravity axis, ~9.8 m/s² at rest)
            // Body Y = Lateral (side-to-side = cornering)
            // Body Z = Longitudinal (front-to-back = braking/accel)
            let point = GPSPoint(
                latitude: data.coordinate.latitude,
                longitude: data.coordinate.longitude,
                altitude: data.altitude,
                speed: data.speed,
                speed3D: data.speed3D,
                timestamp: time,
                gForceLateral: dynY,
                gForceLongitudinal: dynZ,
                gForceVertical: dynX
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
        
        // Filter out extreme geographical jumps and Null Island anomalies
        var validSmoothedPoints = [GPSPoint]()
        
        let validCoords = smoothedPoints.filter { abs($0.latitude) >= 0.01 || abs($0.longitude) >= 0.01 }
        
        if validCoords.isEmpty {
            self.trackPoints = []
            return
        }
        
        // Calculate median latitude and longitude to use as robust center
        let sortedLats = validCoords.map { $0.latitude }.sorted()
        let sortedLons = validCoords.map { $0.longitude }.sorted()
        let medianLat = sortedLats[sortedLats.count / 2]
        let medianLon = sortedLons[sortedLons.count / 2]
        
        for point in validCoords {
            // Filter out points more than 0.5 degrees away (~55km) from the median of the trip
            // This removes cached GPS locations from previous sessions that suddenly jump
            if abs(point.latitude - medianLat) > 0.5 || abs(point.longitude - medianLon) > 0.5 {
                continue
            }
            
            validSmoothedPoints.append(point)
        }
        
        self.trackPoints = validSmoothedPoints
        self.calculateBounds()
        
        // Diagnostic: show G-force range to verify non-zero dynamic values
        let latRange = (smoothedPoints.map { $0.gForceLateral }.min() ?? 0, smoothedPoints.map { $0.gForceLateral }.max() ?? 0)
        let longRange = (smoothedPoints.map { $0.gForceLongitudinal }.min() ?? 0, smoothedPoints.map { $0.gForceLongitudinal }.max() ?? 0)
        let vertRange = (smoothedPoints.map { $0.gForceVertical }.min() ?? 0, smoothedPoints.map { $0.gForceVertical }.max() ?? 0)
        Log.debug("[Telemetry] G-force range (G): LAT=[\(String(format: "%.3f", latRange.0))…\(String(format: "%.3f", latRange.1))] LON=[\(String(format: "%.3f", longRange.0))…\(String(format: "%.3f", longRange.1))] VRT=[\(String(format: "%.3f", vertRange.0))…\(String(format: "%.3f", vertRange.1))]")
        
        // Sample at ~60s mark (should be in-motion)
        if let sample60 = smoothedPoints.first(where: { $0.timestamp >= 60.0 }) {
            Log.debug("[Telemetry] @60s: LAT=\(String(format: "%.3f", sample60.gForceLateral))G LON=\(String(format: "%.3f", sample60.gForceLongitudinal))G VRT=\(String(format: "%.3f", sample60.gForceVertical))G speed=\(String(format: "%.1f", sample60.speed3D * 3.6))km/h")
        }
        
        Log.debug("[Telemetry] Ready. Extracted \(smoothedPoints.count) points.")
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
        let validPoints = trackPoints
        guard !validPoints.isEmpty else { return }
        
        var tempMinLat = validPoints.map { $0.latitude }.min() ?? 0
        var tempMaxLat = validPoints.map { $0.latitude }.max() ?? 0
        var tempMinLon = validPoints.map { $0.longitude }.min() ?? 0
        var tempMaxLon = validPoints.map { $0.longitude }.max() ?? 0
        
        // Prevent flat-line scaling issues if track is perfectly straight or stationary
        if tempMaxLat - tempMinLat < 0.0001 {
            tempMaxLat += 0.0001
            tempMinLat -= 0.0001
        }
        if tempMaxLon - tempMinLon < 0.0001 {
            tempMaxLon += 0.0001
            tempMinLon -= 0.0001
        }
        
        self.minLat = tempMinLat
        self.maxLat = tempMaxLat
        self.minLon = tempMinLon
        self.maxLon = tempMaxLon
    }
    
    /// Returns a plain-value snapshot for the given timestamp.
    /// Callable from any thread — no MainActor required.
    /// Uses the same binary-search logic as updateCurrentTime.
    nonisolated func snapshot(at time: Double) -> TelemetrySnapshot {
        // Capture immutable copies of all needed data
        let points = self.trackPoints
        let minLa = self.minLat
        let maxLa = self.maxLat
        let minLo = self.minLon
        let maxLo = self.maxLon
        
        guard !points.isEmpty else { return TelemetrySnapshot.empty }
        
        // Binary search for the latest point at or before `time`
        var low = 0, high = points.count - 1, index = 0
        while low <= high {
            let mid = (low + high) / 2
            if points[mid].timestamp <= time {
                index = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        let p = points[index]
        return TelemetrySnapshot(
            speed: p.speed3D * 3.6,
            altitude: p.altitude,
            gForceLateral: p.gForceLateral,
            gForceLongitudinal: p.gForceLongitudinal,
            gForceVertical: p.gForceVertical,
            trackPoints: points,
            minLat: minLa,
            maxLat: maxLa,
            minLon: minLo,
            maxLon: maxLo,
            currentTime: time
        )
    }
}

