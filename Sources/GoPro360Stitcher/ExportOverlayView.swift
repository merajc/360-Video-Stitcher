import SwiftUI

struct ExportOverlayView: View {
    @ObservedObject var telemetry: TelemetryProcessor
    var currentTime: Double
    var size: CGSize
    var showTrackMap: Bool
    var showDashboard: Bool
    var showSpeed: Bool
    var showAltitude: Bool
    var showGForce: Bool
    var scale: Double
    
    var body: some View {
        let uiScale = scale * (size.width / 1080.0)
        
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    if showTrackMap {
                        TrackMapView(telemetry: telemetry, currentTime: currentTime)
                            .frame(width: 150 * uiScale, height: 150 * uiScale)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .padding(20 * uiScale)
                    }
                }
                Spacer()
                if showDashboard {
                    TelemetryDashboardView(telemetry: telemetry, showSpeed: showSpeed, showAltitude: showAltitude, showGForce: showGForce)
                        .scaleEffect(uiScale, anchor: .bottomTrailing)
                        .padding(.bottom, 40 * uiScale)
                        .padding(.trailing, 20 * uiScale)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
