import Metal
import MetalKit

class EACRenderer {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var computePipelineState: MTLComputePipelineState!
    
    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        
        // Load default library
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "eacToRectilinear") else {
            print("Failed to load Metal shader eacToRectilinear")
            return nil
        }
        
        do {
            self.computePipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            print("Compute pipeline error: \(error)")
            return nil
        }
    }
    
    func render(inputTexture: MTLTexture, outputTexture: MTLTexture, pan: Float, tilt: Float, roll: Float, fov: Float = .pi / 2) {
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
        
        let w = computePipelineState.threadExecutionWidth
        let h = computePipelineState.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}
