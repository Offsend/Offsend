import XCTest
@testable import DetectionCore

final class RecommendedAIModelCatalogTests: XCTestCase {
    func testCatalogIsNotEmpty() {
        XCTAssertFalse(RecommendedAIModelCatalog.models.isEmpty)
    }

    func testLookupByRepositoryID() {
        XCTAssertEqual(
            RecommendedAIModelCatalog.model(for: "Isotonic/mdeberta-v3-base_finetuned_ai4privacy_v2")?.title,
            "mDeBERTa PII"
        )
    }

    func testRepositoryIDsAreUnique() {
        let ids = RecommendedAIModelCatalog.models.map(\.repositoryID)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCatalogExcludesNonONNXOnlyModels() {
        let ids = Set(RecommendedAIModelCatalog.models.map(\.repositoryID))
        XCTAssertFalse(ids.contains("dslim/bert-base-NER"))
        XCTAssertFalse(ids.contains("urchade/gliner_multi-v2.1"))
        XCTAssertFalse(ids.contains("exdsgift/NerGuard-0.3B"))
    }

    func testCatalogIncludesONNXNerGuardVariant() {
        XCTAssertNotNil(RecommendedAIModelCatalog.model(for: "exdsgift/NerGuard-0.3B-onnx-int8"))
    }
}
