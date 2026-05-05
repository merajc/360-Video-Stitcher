import Foundation

func test() {
    nonisolated(unsafe) var x: Int = 0
    let sem = DispatchSemaphore(value: 0)
    Task {
        x = 5
        sem.signal()
    }
    sem.wait()
    print(x)
}
test()
