import SwiftUI
import UniformTypeIdentifiers

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

struct ContentView: View {
    @State private var pan: Double = 0
    @State private var tilt: Double = 0
    @State private var roll: Double = 0
    @State private var isTargeted = false
    @StateObject private var processor = VideoProcessor()
    
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
                    } else if processor.composition != nil {
                        // The actual video preview will go here
                        ZStack {
                            Rectangle()
                                .fill(Color.black)
                            
                            VStack(spacing: 2) {
                                Text("FRONT VIEW (0°)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Divider().background(Color.white.opacity(0.2))
                                Spacer()
                                Text("REAR VIEW (180°)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding()
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
                VStack(alignment: .leading, spacing: 25) {
                    Text("360 REFRAMING")
                        .font(.system(.caption, design: .rounded))
                        .kerning(2)
                        .foregroundColor(.secondary)
                        .padding(.top, 10)
                    
                    ControlSlider(label: "PAN", value: $pan, range: -180...180, unit: "°")
                    ControlSlider(label: "TILT", value: $tilt, range: -90...90, unit: "°")
                    ControlSlider(label: "ROLL", value: $roll, range: -180...180, unit: "°")
                    
                    Divider().padding(.vertical, 10)
                    
                    Text("OVERLAYS")
                        .font(.system(.caption, design: .rounded))
                        .kerning(2)
                        .foregroundColor(.secondary)
                    
                    Toggle("GPS TRACK MAP", isOn: .constant(true))
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                    
                    Spacer()
                    
                    Button(action: {
                        exportVideo()
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("GENERATE 9:16 VIDEO")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .disabled(processor.composition == nil)
                    
                    Text("M4 MEDIA ENGINE ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green.opacity(0.8))
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
                .frame(width: 280)
                .background(
                    VisualEffect(material: .sidebar, blendingMode: .withinWindow)
                        .ignoresSafeArea()
                )
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
    
    private func exportVideo() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.nameFieldStringValue = "GoPro_Edit.mp4"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                Task {
                    try? await processor.exportVideo(to: url)
                }
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
