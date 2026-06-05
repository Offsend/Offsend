import DetectionCore
import RiskScoringCore
@testable import DocumentCore

enum RedactionFixtures {
    static func analysis(
        plainText: String,
        format: DocumentFormat = .pdf,
        entities: [SensitiveEntity]
    ) -> DocumentAnalysisResult {
        DocumentAnalysisResult(
            extracted: ExtractedDocument(
                source: DocumentSource(fileName: "sample.pdf"),
                format: format,
                plainText: plainText,
                characterCount: plainText.count,
                wasTruncated: false,
                extractorID: "pdf"
            ),
            detection: DetectionResult(
                entities: entities,
                scannedText: plainText,
                wasTruncated: false,
                scannedCharacterCount: plainText.count
            ),
            assessment: RiskAssessment(
                score: 10,
                level: .low,
                recommendedAction: .allow,
                hasCriticalSecret: false
            )
        )
    }

    static func entity(
        type: SensitiveEntityType,
        value: String,
        in text: String
    ) -> SensitiveEntity {
        let range = text.range(of: value) ?? value.startIndex..<value.endIndex
        return SensitiveEntity(
            type: type,
            range: range,
            value: value,
            confidence: 1,
            source: .regex
        )
    }
}
