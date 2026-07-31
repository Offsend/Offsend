import Foundation

enum AIModelLoadState: Equatable {
    case idle
    case loading(displayName: String)
    case ready(displayName: String)
    case failed(displayName: String, message: String)
}
