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
    
    func renderStacked(front: CVPixelBuffer, rear: CVPixelBuffer, to output: CVPixelBuffer, topParams: SIMD4<Float>, bottomParams: SIMD4<Float>) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder(),
              let textureOutput = makeTexture(from: output),
              let textureFront = makeTexture(from: front),
              let textureRear = makeTexture(from: rear) else { return }
        
        encoder.setComputePipelineState(computePipelineState)
        
        // Convert degrees to radians for the shader
        var tParams = topParams
        tParams.x *= .pi/180 // tilt
        tParams.y *= .pi/180 // pan
        tParams.z *= .pi/180 // roll
        tParams.w *= .pi/180 // fov
        
        var bParams = bottomParams
        bParams.x *= .pi/180 // tilt
        bParams.y *= .pi/180 // pan
        bParams.z *= .pi/180 // roll
        bParams.w *= .pi/180 // fov
        
        encoder.setBytes(&tParams, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.setBytes(&bParams, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
        
        encoder.setTexture(textureFront, index: 0)
        encoder.setTexture(textureRear, index: 1)
        encoder.setTexture(textureOutput, index: 2)
        
        let threadsPerThreadgroup = MTLSizeMake(16, 16, 1)
        let threadsPerGrid = MTLSizeMake(textureOutput.width, textureOutput.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
    }
    
    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache = textureCache else { return nil }
        var texture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &texture)
        guard let texture = texture else { return nil }
        return CVMetalTextureGetTexture(texture)
    }
}
