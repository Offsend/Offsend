import Foundation
import OnnxRuntimeBindings
import DetectionCore

public enum ONNXRuntimeExecutionBackend: Equatable, Sendable {
    case coreML
    case cpu
}

public enum ONNXRuntimeSessionBuilder {
    /// Creates an ORT session, preferring Core ML (ANE/GPU) when the EP is available.
    public static func makeSession(env: ORTEnv, modelPath: String) throws -> (session: ORTSession, backend: ONNXRuntimeExecutionBackend) {
        let sessionOptions = try ORTSessionOptions()
        _ = try sessionOptions.setIntraOpNumThreads(2)

        var backend: ONNXRuntimeExecutionBackend = .cpu
        if ORTIsCoreMLExecutionProviderAvailable() {
            let coreML = ORTCoreMLExecutionProviderOptions()
            coreML.createMLProgram = true
            coreML.onlyAllowStaticInputShapes = true
            do {
                try sessionOptions.appendCoreMLExecutionProvider(with: coreML)
                backend = .coreML
            } catch {
                backend = .cpu
            }
        }

        let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: sessionOptions)
        return (session, backend)
    }
}
