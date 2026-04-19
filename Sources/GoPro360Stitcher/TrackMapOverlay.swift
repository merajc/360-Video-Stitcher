import SwiftUI
import CoreGraphics
import CoreLocation

struct TrackMapOverlay {
    /// Generates a CGPath from GPS coordinates scaled to fit a given rect
    func createTrackPath(coordinates: [CLLocationCoordinate2D], in rect: CGRect) -> CGPath? {
        guard coordinates.count > 1 else { return nil }
        
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        
        guard latRange > 0 && lonRange > 0 else { return nil }
        
        let path = CGMutablePath()
        let padding: CGFloat = 20
        let drawRect = rect.insetBy(dx: padding, dy: padding)
        
        for (index, coord) in coordinates.enumerated() {
            // Normalize coordinates
            let x = CGFloat((coord.longitude - minLon) / lonRange) * drawRect.width + drawRect.origin.x
            // Latitude increases upwards, but CG coordinates usually downwards
            let y = CGFloat(1.0 - (coord.latitude - minLat) / latRange) * drawRect.height + drawRect.origin.y
            
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        
        return path
    }
    
    /// Renders the track map to an image
    func renderTrackImage(coordinates: [CLLocationCoordinate2D], size: CGSize) -> NSImage? {
        let image = NSImage(size: size)
        
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            if let path = createTrackPath(coordinates: coordinates, in: CGRect(origin: .zero, size: size)) {
                context.setStrokeColor(NSColor.systemYellow.cgColor)
                context.setLineWidth(3.0)
                context.setLineJoin(.round)
                context.setLineCap(.round)
                context.addPath(path)
                context.strokePath()
            }
        }
        image.unlockFocus()
        
        return image
    }
}
