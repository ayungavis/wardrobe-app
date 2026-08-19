import Foundation

extension GarmentMask {
    struct Repaired {
        let mask: Mask
        let holes: [UInt8]
        let quality: Float
    }

    private static let strayThreshold = 0.05

    static func repair(_ mask: Mask) -> Repaired? {
        let stripped = dropStrayComponents(mask)
        guard stripped.kept > 0 else { return nil }

        let closed = closeHoles(stripped.pixels, width: mask.width, height: mask.height)
        guard let bounds = bounds(of: closed.filled, width: mask.width) else { return nil }

        let garment = Double(stripped.kept)
        let quality = 1 - 0.5 * (Double(closed.area) / garment) - 0.5 * (Double(stripped.dropped) / garment)

        return Repaired(
            mask: Mask(pixels: closed.filled, width: mask.width, height: mask.height, bounds: bounds),
            holes: closed.holes,
            quality: Float(min(1, max(0, quality)))
        )
    }

    // MARK: Stray components

    struct Stripped {
        let pixels: [UInt8]
        let kept: Int
        let dropped: Int
    }

    private static func dropStrayComponents(_ mask: Mask) -> Stripped {
        let components = connectedComponents(mask.pixels, width: mask.width, height: mask.height)
        guard let largest = components.map(\.count).max() else {
            return Stripped(pixels: mask.pixels, kept: 0, dropped: 0)
        }

        let minimum = max(2, Int((Double(largest) * strayThreshold).rounded(.up)))
        var pixels = [UInt8](repeating: 0, count: mask.pixels.count)
        var kept = 0
        var dropped = 0

        for component in components {
            guard component.count >= minimum else {
                dropped += component.count
                continue
            }
            for index in component {
                pixels[index] = 255
            }
            kept += component.count
        }
        return Stripped(pixels: pixels, kept: kept, dropped: dropped)
    }

    private static func connectedComponents(_ pixels: [UInt8], width: Int, height: Int) -> [[Int]] {
        var visited = [Bool](repeating: false, count: pixels.count)
        var components: [[Int]] = []

        for start in pixels.indices where pixels[start] == 255 && !visited[start] {
            var component: [Int] = []
            var queue = [start]
            visited[start] = true

            while let index = queue.popLast() {
                component.append(index)
                for neighbour in neighbours(of: index, width: width, height: height) {
                    guard pixels[neighbour] == 255, !visited[neighbour] else { continue }
                    visited[neighbour] = true
                    queue.append(neighbour)
                }
            }
            components.append(component)
        }
        return components
    }

    // MARK: Holes

    struct Closed {
        let filled: [UInt8]
        let holes: [UInt8]
        let area: Int
    }

    private static func closeHoles(
        _ pixels: [UInt8],
        width: Int,
        height: Int
    ) -> Closed {
        var outside = [Bool](repeating: false, count: pixels.count)
        var queue: [Int] = []

        for column in 0 ..< width {
            queue.append(column)
            queue.append((height - 1) * width + column)
        }
        for row in 0 ..< height {
            queue.append(row * width)
            queue.append(row * width + width - 1)
        }
        queue = queue.filter { pixels[$0] == 0 }
        for index in queue {
            outside[index] = true
        }

        while let index = queue.popLast() {
            for neighbour in neighbours(of: index, width: width, height: height) {
                guard pixels[neighbour] == 0, !outside[neighbour] else { continue }
                outside[neighbour] = true
                queue.append(neighbour)
            }
        }

        var filled = pixels
        var holes = [UInt8](repeating: 0, count: pixels.count)
        var area = 0
        for index in pixels.indices where pixels[index] == 0 && !outside[index] {
            filled[index] = 255
            holes[index] = 255
            area += 1
        }
        return Closed(filled: filled, holes: holes, area: area)
    }

    // MARK: Helpers

    private static func neighbours(of index: Int, width: Int, height: Int) -> [Int] {
        let row = index / width
        let column = index % width
        var result: [Int] = []
        if column > 0 {
            result.append(index - 1)
        }
        if column < width - 1 {
            result.append(index + 1)
        }
        if row > 0 {
            result.append(index - width)
        }
        if row < height - 1 {
            result.append(index + width)
        }
        return result
    }

    private static func bounds(of pixels: [UInt8], width: Int) -> Bounds? {
        var bounds: Bounds?
        for index in pixels.indices where pixels[index] == 255 {
            let row = index / width
            let column = index % width
            if var box = bounds {
                box.minX = min(box.minX, column)
                box.maxX = max(box.maxX, column)
                box.minY = min(box.minY, row)
                box.maxY = max(box.maxY, row)
                bounds = box
            } else {
                bounds = Bounds(minX: column, maxX: column, minY: row, maxY: row)
            }
        }
        return bounds
    }
}
