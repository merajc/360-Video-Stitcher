import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
                    .shadow(color: Color.blue.opacity(0.3), radius: configuration.isPressed ? 2 : 10, x: 0, y: configuration.isPressed ? 2 : 5)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ControlSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(value, specifier: "%.1f")\(unit)")
                    .font(.system(.subheadline, design: .monospaced))
                    .bold()
            }
            Slider(value: $value, in: range)
                .tint(.blue)
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

struct Seekbar: View {
    @ObservedObject var processor: VideoProcessor
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: {
                isDragging ? dragValue : (processor.player?.currentTime().seconds ?? 0)
            }, set: { newValue in
                dragValue = newValue
                isDragging = true
                processor.player?.seek(to: CMTime(seconds: newValue, preferredTimescale: 600))
            }), in: 0...(processor.composition?.duration.seconds ?? 1)) {
                Text("Seek bar")
            } onEditingChanged: { editing in
                isDragging = editing
            }
            .tint(.blue)
            
            HStack {
                Text(formatTime(isDragging ? dragValue : (processor.player?.currentTime().seconds ?? 0)))
                Spacer()
                Text(formatTime(processor.composition?.duration.seconds ?? 1))
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .onReceive(timer) { _ in
            // Force view refresh to update timeline text
            if !isDragging {
                // Just trigger re-render
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct ContentView: View {
    @State private var isTargeted = false
    @StateObject private var processor = VideoProcessor()
    @State private var currentTime: Double = 0
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Background mesh/gradient for a premium feel
            Color.black.ignoresSafeArea()
            
            HStack(spacing: 0) {
                // Main Preview Area
                VStack(spacing: 0) {
                    if processor.isLoading {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Engine Initializing...")
                                .font(.headline)
                                .italic()
                        }
                    } else if processor.isExporting {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Rendering Video...")
                                .font(.headline)
                            
                            VStack(spacing: 8) {
                                ProgressView(value: processor.exportProgress, total: 1.0)
                                    .progressViewStyle(.linear)
                                    .frame(width: 300)
                                Text("\(Int(processor.exportProgress * 100))%")
                                    .font(.title3.monospaced())
                                    .bold()
                            }
                        }
                    } else if let player = processor.player {
                        VStack(spacing: 20) {
                            // 9:16 Viewport
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black)
                                    .shadow(color: .black.opacity(0.5), radius: 20)
                                
                                PlayerView(player: player)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                // Viewport Guide Overlay
                                VStack {
                                    HStack {
                                        Text("9:16 EAC SPHERICAL")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .padding(6)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(6)
                                        Spacer()
                                        
                                        if processor.showTrackMap {
                                            TrackMapView(telemetry: processor.telemetry, currentTime: currentTime)
                                                .frame(width: 100, height: 100)
                                                .background(Color.black.opacity(0.3))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                        }
                                    }
                                    Spacer()
                                    if processor.showTelemetryDashboard && !processor.telemetry.trackPoints.isEmpty {
                                        TelemetryDashboardView(
                                            telemetry: processor.telemetry,
                                            showSpeed: processor.showSpeedGauge,
                                            showAltitude: processor.showAltitudeGauge,
                                            showGForce: processor.showGForceGauge
                                        )
                                            .scaleEffect(processor.telemetryScale, anchor: .bottomTrailing)
                                            .padding(.bottom, 20)
                                    }
                                }
                                .padding(10)
                            }
                            .aspectRatio(9/16, contentMode: .fit)
                            .frame(maxHeight: 700) // Constrain height to keep it manageable
                            .padding(.top, 40)
                            .padding(.bottom, 20)
                            
                            // Seekbar + Transport Controls
                            VStack(spacing: 12) {
                                HStack(spacing: 20) {
                                    // Close File
                                    Button(action: {
                                        processor.closeFile()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Close File")
                                    
                                    Spacer()
                                    
                                    // Play/Pause
                                    Button(action: {
                                        processor.togglePlayback()
                                    }) {
                                        Image(systemName: processor.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 36))
                                            .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Spacer()
                                    
                                    // Spatial Audio indicator
                                    HStack(spacing: 4) {
                                        Image(systemName: processor.exportSpatialAudio ? "hifispeaker.and.homepodmini.fill" : "speaker.2.fill")
                                            .font(.caption)
                                        Text(processor.exportSpatialAudio ? "Spatial" : "Stereo")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                    }
                                    .foregroundColor(processor.exportSpatialAudio ? .cyan : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.white.opacity(0.1)))
                                }
                                .frame(width: 400)
                                
                                Seekbar(processor: processor)
                                    .frame(width: 400)
                            }
                            .padding(.bottom, 40)
                        }
                    } else {
                        VStack(spacing: 15) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 60))
                                .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                            
                            Text("Drop GoPro .360 Chapters")
                                .font(.title2.bold())
                            
                            Text("Sequential files will be virtually stitched")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                selectFiles()
                            }) {
                                Text("Select Files Manually")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.blue.opacity(0.2)))
                                    .overlay(Capsule().stroke(Color.blue, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                        }
                        .padding(40)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .strokeBorder(isTargeted ? Color.blue : Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 2, dash: [10]))
                        )
                        .scaleEffect(isTargeted ? 1.02 : 1.0)
                        .animation(.easeInOut, value: isTargeted)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Sidebar Controls
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        // TOP VIEW SECTION
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TOP VIEW (TRACK)")
                                .font(.system(.caption, design: .rounded))
                                .kerning(2)
                                .foregroundColor(.blue)
                                .bold()
                            
                            ControlSlider(label: "PAN", value: $processor.topPan, range: -180...180, unit: "°")
                            ControlSlider(label: "TILT", value: $processor.topTilt, range: -90...90, unit: "°")
                            ControlSlider(label: "ROLL", value: $processor.topRoll, range: -180...180, unit: "°")
                            ControlSlider(label: "ZOOM", value: $processor.topFOV, range: 40...160, unit: "°")
                            
                            HStack {
                                Toggle("FLIP HORIZONTAL", isOn: $processor.topFlipH)
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                                Toggle("FLIP VERTICAL", isOn: $processor.topFlipV)
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                            }
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                        .padding(.top, 10)
                        
                        Divider().opacity(0.2)
                        
                        // BOTTOM VIEW SECTION
                        VStack(alignment: .leading, spacing: 12) {
                            Text("BOTTOM VIEW (DRIVER)")
                                .font(.system(.caption, design: .rounded))
                                .kerning(2)
                                .foregroundColor(.purple)
                                .bold()
                            
                            ControlSlider(label: "PAN", value: $processor.bottomPan, range: -180...180, unit: "°")
                            ControlSlider(label: "TILT", value: $processor.bottomTilt, range: -90...90, unit: "°")
                            ControlSlider(label: "ROLL", value: $processor.bottomRoll, range: -180...180, unit: "°")
                            ControlSlider(label: "ZOOM", value: $processor.bottomFOV, range: 40...160, unit: "°")
                            
                            HStack {
                                Toggle("FLIP HORIZONTAL", isOn: $processor.bottomFlipH)
                                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                                Toggle("FLIP VERTICAL", isOn: $processor.bottomFlipV)
                                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                            }
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                        
                        Divider().opacity(0.2)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OVERLAYS")
                                .font(.system(.caption, design: .rounded))
                                .kerning(2)
                                .foregroundColor(.secondary)
                            
                            Toggle("GPS TRACK MAP", isOn: $processor.showTrackMap)
                                .font(.headline)
                            
                            Toggle("TELEMETRY DASHBOARD", isOn: $processor.showTelemetryDashboard)
                                .font(.headline)
                            
                            if processor.showTelemetryDashboard {
                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle("Speed", isOn: $processor.showSpeedGauge)
                                        .controlSize(.mini)
                                    
                                    Toggle("Altitude", isOn: $processor.showAltitudeGauge)
                                        .controlSize(.mini)
                                    
                                    Toggle("G-Force", isOn: $processor.showGForceGauge)
                                        .toggleStyle(SwitchToggleStyle(tint: .cyan))
                                        .font(.caption)
                                    
                                    HStack {
                                        Text("Scale")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Slider(value: $processor.telemetryScale, in: 0.1...3.0)
                                            .tint(.cyan)
                                    }
                                    .padding(.top, 4)
                                }
                                .padding(.leading, 12)
                            }
                        }
                        
                        Spacer(minLength: 20)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("EXPORT SETTINGS")
                                .font(.system(.caption, design: .rounded))
                                .kerning(2)
                                .foregroundColor(.secondary)
                            
                            Picker("Resolution", selection: $processor.exportResolution) {
                                ForEach(ExportResolution.allCases) { res in
                                    Text(res.rawValue).tag(res)
                                }
                            }
                            
                            Picker("Codec", selection: $processor.exportCodec) {
                                ForEach(ExportCodec.allCases) { codec in
                                    Text(codec.rawValue).tag(codec)
                                }
                            }
                            
                            if processor.exportCodec == .hevc {
                                Picker("Bitrate", selection: $processor.exportBitrate) {
                                    ForEach(ExportBitrate.allCases) { bitrate in
                                        Text(bitrate.rawValue).tag(bitrate)
                                    }
                                }
                            }
                            
                            Toggle("Spatial Audio (Ambisonics)", isOn: $processor.exportSpatialAudio)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .onChange(of: processor.exportSpatialAudio) { _, _ in
                                    Task {
                                        await processor.reloadAudioTrack()
                                    }
                                }
                        }
                        .pickerStyle(MenuPickerStyle())
                        
                        Spacer(minLength: 20)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("BATCH QUEUE")
                                .font(.system(.caption, design: .rounded))
                                .kerning(2)
                                .foregroundColor(.secondary)
                            
                            if !processor.batchQueue.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(processor.batchQueue) { job in
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(job.name)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                
                                                if case .failed(let err) = job.status {
                                                    Text(err)
                                                        .font(.caption2)
                                                        .foregroundColor(.red)
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer()
                                            
                                            switch job.status {
                                            case .pending:
                                                Image(systemName: "clock")
                                                    .foregroundColor(.secondary)
                                            case .exporting:
                                                ProgressView()
                                                    .scaleEffect(0.5)
                                                    .frame(width: 16, height: 16)
                                            case .completed:
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                            case .failed:
                                                Image(systemName: "exclamationmark.circle.fill")
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            
                            HStack(spacing: 10) {
                                Button(action: {
                                    addToQueue()
                                }) {
                                    HStack {
                                        Image(systemName: "plus")
                                        Text("ADD")
                                            .bold()
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PremiumButtonStyle())
                                .disabled(processor.composition == nil || processor.isExporting)
                                
                                Button(action: {
                                    Task {
                                        await processor.startBatchExport()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("START")
                                            .bold()
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PremiumButtonStyle())
                                .disabled(processor.batchQueue.filter { $0.status == .pending || $0.status == .failed("Retry") }.isEmpty || processor.isExporting)
                            }
                        }
                        
                        Text("M4 MEDIA ENGINE ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green.opacity(0.8))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                }
                .frame(width: 300)
                .background(
                    VisualEffect(material: .sidebar, blendingMode: .withinWindow)
                        .ignoresSafeArea()
                )
            }
        }
        .onReceive(timer) { _ in
            if let p = processor.player {
                currentTime = p.currentTime().seconds
                processor.telemetry.updateCurrentTime(currentTime)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let item = try? await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) as? Data,
                       let url = URL(dataRepresentation: item, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                await processor.processFiles(urls: urls)
            }
            return true
        }
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "360")!]
        
        panel.begin { result in
            if result == .OK {
                Task {
                    await processor.processFiles(urls: panel.urls)
                }
            }
        }
    }
    
    private func addToQueue() {
        let savePanel = NSSavePanel()
        
        let isHevc = processor.exportCodec == .hevc
        savePanel.allowedContentTypes = isHevc ? [.mpeg4Movie] : [.quickTimeMovie]
        savePanel.nameFieldStringValue = isHevc ? "GoPro_Edit_\(processor.batchQueue.count + 1).mp4" : "GoPro_Edit_\(processor.batchQueue.count + 1).mov"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                processor.addToQueue(name: url.lastPathComponent, outputUrl: url)
            }
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
