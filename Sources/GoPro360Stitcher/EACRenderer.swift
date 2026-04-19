import Metal
import MetalKit

class EACRenderer {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var computePipelineState: MTLComputePipelineState!
    
    private var textureCache: CVMetalTextureCache?
    
    init?() {
        print("🎨 [Renderer] Initializing Metal Pipeline...")
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("❌ [Renderer] Failed to create Metal Device or Command Queue.")
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        // Load Metal Library from resources
        var library: MTLLibrary?
        if let shaderURL = Bundle.module.url(forResource: "EACShader", withExtension: "metal"),
           let shaderSource = try? String(contentsOf: shaderURL) {
            print("🎨 [Renderer] Found EACShader.metal in bundle. Compiling...")
            library = try? device.makeLibrary(source: shaderSource, options: nil)
        } else {
            print("🎨 [Renderer] Shader resource not found, falling back to default library.")
            library = device.makeDefaultLibrary()
        }
        
        guard let finalLibrary = library,
              let function = finalLibrary.makeFunction(name: "renderStackedView") else {
            print("❌ [Renderer] Failed to load Metal function 'renderStackedView'")
            return nil
        }
        
        do {
            self.computePipelineState = try device.makeComputePipelineState(function: function)
            print("✅ [Renderer] Metal Engine Ready.")
        } catch {
            print("❌ [Renderer] Pipeline state error: \(error)")
            return nil
        }
    }
    
    func render(pixelBuffer: CVPixelBuffer, outputTexture: MTLTexture, pan: Float, tilt: Float, roll: Float, fov: Float = .pi / 2) {
        guard let textureCache = textureCache else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        
        guard let cvTexture = cvTexture, let inputTexture = CVMetalTextureGetTexture(cvTexture) else { return }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.setComputePipelineState(computePipelineState)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        var eulerAngles = SIMD3<Float>(tilt * .pi/180, pan * .pi/180, roll * .pi/180)
        encoder.setBytes(&eulerAngles, length: MemoryLayout.size(ofValue: eulerAngles), index: 0)
        
        var fovRad = fov
        encoder.setBytes(&fovRad, length: MemoryLayout.size(ofValue: fovRad), index: 1)
        
        let threadsPerThreadgroup = MTLSizeMake(16, 16, 1)
        let threadsPerGrid = MTLSizeMake((outputTexture.width + 15) / 16 * 16, (outputTexture.height + 15) / 16 * 16, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
    }
}
