import Foundation

enum ONNXTensorHelpers {
    static func dataCopiedFromArray<T>(_ array: [T]) -> Data {
        array.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func floatArray(from data: Data) -> [Float]? {
        guard data.count % MemoryLayout<Float>.stride == 0 else { return nil }
        return data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }

    static func argmaxPerRow(logits: [Float], sequenceLength: Int, labelCount: Int) -> [Int] {
        guard sequenceLength > 0, labelCount > 0, logits.count >= sequenceLength * labelCount else {
            return []
        }
        var labels = [Int]()
        labels.reserveCapacity(sequenceLength)
        for position in 0 ..< sequenceLength {
            let offset = position * labelCount
            var bestIndex = 0
            var bestValue = logits[offset]
            for label in 1 ..< labelCount {
                let value = logits[offset + label]
                if value > bestValue {
                    bestValue = value
                    bestIndex = label
                }
            }
            labels.append(bestIndex)
        }
        return labels
    }

    static func softmaxConfidence(logits: [Float], sequenceLength: Int, labelCount: Int, labels: [Int]) -> [Double] {
        guard labels.count == sequenceLength else { return [] }
        var confidences = [Double]()
        confidences.reserveCapacity(sequenceLength)
        for position in 0 ..< sequenceLength {
            let offset = position * labelCount
            let slice = logits[offset ..< offset + labelCount]
            let maxLogit = slice.max() ?? 0
            var sum: Float = 0
            var expValues = [Float]()
            expValues.reserveCapacity(labelCount)
            for logit in slice {
                let expValue = expf(logit - maxLogit)
                expValues.append(expValue)
                sum += expValue
            }
            let label = labels[position]
            let confidence = sum > 0 ? Double(expValues[label] / sum) : 0.5
            confidences.append(confidence)
        }
        return confidences
    }
}
