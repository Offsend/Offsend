import CoreML
import Foundation

enum CoreMLMultiArrayHelpers {
    static func featureValue(
        integers: [Int64],
        description: MLFeatureDescription,
        length: Int
    ) throws -> MLFeatureValue {
        let shape: [NSNumber] = [1, NSNumber(value: length)]
        let dataType = description.multiArrayConstraint?.dataType ?? .int32

        switch dataType {
        case .int32:
            let array = try MLMultiArray(shape: shape, dataType: .int32)
            for index in 0 ..< length {
                array[[0, NSNumber(value: index)]] = NSNumber(value: Int32(integers[index]))
            }
            return MLFeatureValue(multiArray: array)
        case .double:
            let array = try MLMultiArray(shape: shape, dataType: .double)
            for index in 0 ..< length {
                array[[0, NSNumber(value: index)]] = NSNumber(value: Double(integers[index]))
            }
            return MLFeatureValue(multiArray: array)
        default:
            let array = try MLMultiArray(shape: shape, dataType: .int32)
            for index in 0 ..< length {
                array[[0, NSNumber(value: index)]] = NSNumber(value: Int32(integers[index]))
            }
            return MLFeatureValue(multiArray: array)
        }
    }

    static func floatArray(from feature: MLFeatureValue) throws -> [Float] {
        guard let multiArray = feature.multiArrayValue else {
            throw AIModelRuntimeError.inferenceFailed("Core ML output is not a multi-array.")
        }
        switch multiArray.dataType {
        case .float32:
            return (0 ..< multiArray.count).map { index in
                multiArray[index].floatValue
            }
        case .double:
            return (0 ..< multiArray.count).map { index in
                Float(multiArray[index].doubleValue)
            }
        default:
            throw AIModelRuntimeError.inferenceFailed("Unsupported Core ML logits data type.")
        }
    }
}
