import SwiftUI

@MainActor
func test() {
    let view = Text("Hello")
    let renderer = ImageRenderer(content: view)
    let cgImage = renderer.cgImage
    print(cgImage != nil)
}
test()
