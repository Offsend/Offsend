import Foundation

public struct RecommendedAIModel: Identifiable, Equatable, Sendable {
    public let repositoryID: String
    public let title: String
    public let detail: String
    /// When true, download requires a Hugging Face access token.
    public let requiresToken: Bool

    public var id: String { repositoryID }

    public init(repositoryID: String, title: String, detail: String, requiresToken: Bool = false) {
        self.repositoryID = repositoryID
        self.title = title
        self.detail = detail
        self.requiresToken = requiresToken
    }
}

public enum RecommendedAIModelCatalog {
    /// Curated Hugging Face repos that ship ONNX token-classification weights runnable in Offsend.
    public static let models: [RecommendedAIModel] = [
        RecommendedAIModel(
            repositoryID: "Isotonic/mdeberta-v3-base_finetuned_ai4privacy_v2",
            title: "mDeBERTa PII",
            detail: "PII token classification · ONNX in onnx/ · ~400 MB"
        ),
        RecommendedAIModel(
            repositoryID: "onnx-community/multilang-pii-ner-ONNX",
            title: "Multilingual PII NER",
            detail: "EN/DE/IT/FR PII · ONNX quantized variants"
        ),
        RecommendedAIModel(
            repositoryID: "exdsgift/NerGuard-0.3B-onnx-int8",
            title: "NerGuard 0.3B (ONNX int8)",
            detail: "20 PII types · gated Hugging Face repo",
            requiresToken: true
        ),
    ]

    public static func model(for repositoryID: String) -> RecommendedAIModel? {
        models.first { $0.repositoryID == repositoryID }
    }
}
