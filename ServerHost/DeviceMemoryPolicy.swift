import Foundation

enum DeviceMemoryPolicy {
    static let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
    static let physicalMemoryGB = Double(physicalMemoryBytes) / 1_073_741_824

    static var maximumJavaHeapMB: Double {
        let physicalMB = Double(physicalMemoryBytes) / 1_048_576
        let memoryBudget = min(physicalMB * 0.625, physicalMB - 1_536)
        let rounded = floor(max(512, memoryBudget) / 256) * 256
        return min(8_192, max(512, rounded))
    }

    static var recommendedAllocationMB: Double {
        maximumJavaHeapMB
    }

    static func clampedAllocation(_ requestedMB: Double) -> Double {
        min(maximumJavaHeapMB, max(512, requestedMB.isFinite ? requestedMB : recommendedAllocationMB))
    }

    static func clampedPlayerCount(_ requested: Double) -> Int {
        Int(min(1_000_000, max(1, requested.isFinite ? requested : 20)))
    }
}
