import Foundation

enum TokenClassificationDecoder {
    static let defaultMaxLength = 512
    /// Token overlap between adjacent windows so an entity split across a window edge is still seen whole.
    static let chunkStride = 128
    /// Spans whose worst-case softmax probability is below this are dropped to curb false positives.
    static let minConfidence = 0.5

    static func detect(
        text: String,
        tokenizer: HFTokenizer,
        config: HFModelConfig,
        options: DetectionOptions,
        maxLength: Int,
        runLogits: ([HFEncodedToken]) throws -> [Float]
    ) throws -> [SensitiveEntity] {
        let boundedMax = max(min(config.maxPositionEmbeddings, maxLength), 3)
        // Token ranges point into the full `text`, so windowing over tokens needs no offset remap.
        let content = tokenizer.encodeContentTokens(text: text)
        guard !content.isEmpty else { return [] }

        let windowSize = max(boundedMax - 2, 1)
        let overlap = min(chunkStride, windowSize / 2)
        let stride = max(windowSize - overlap, 1)

        var entities: [SensitiveEntity] = []
        var windowStart = 0
        while windowStart < content.count {
            let windowEnd = min(windowStart + windowSize, content.count)
            var windowTokens = [tokenizer.classifierStartToken]
            windowTokens.append(contentsOf: content[windowStart..<windowEnd])
            windowTokens.append(tokenizer.separatorToken)
            let padded = tokenizer.pad(windowTokens, to: boundedMax)

            let logits = try runLogits(padded)
            entities += decodeEntities(
                text: text,
                tokens: padded,
                logits: logits,
                config: config,
                options: options,
                padToken: tokenizer.padToken
            )

            if windowEnd == content.count { break }
            windowStart += stride
        }
        return mergeWindowOverlaps(entities, in: text)
    }

    static func decodeEntities(
        text: String,
        tokens: [HFEncodedToken],
        logits: [Float],
        config: HFModelConfig,
        options: DetectionOptions,
        padToken: Int64
    ) -> [SensitiveEntity] {
        let labelCount = config.id2label.count
        let sequenceLength = min(tokens.count, logits.count / max(labelCount, 1))
        let predicted = ONNXTensorHelpers.argmaxPerRow(
            logits: logits,
            sequenceLength: sequenceLength,
            labelCount: labelCount
        )
        let confidences = ONNXTensorHelpers.softmaxConfidence(
            logits: logits,
            sequenceLength: sequenceLength,
            labelCount: labelCount,
            labels: predicted
        )

        var tokenRanges: [Range<String.Index>] = []
        var labels: [String] = []
        var tokenConfidences: [Double] = []
        // Hugging Face "first subword" strategy: a word's entity is set by its first token and the
        // remaining subword pieces inherit it, so a span is never cut where the model emits `O` mid-word.
        var currentWordEntity: String?

        for (index, token) in tokens.prefix(sequenceLength).enumerated() {
            guard !token.isSpecial, token.id != padToken else {
                currentWordEntity = nil
                continue
            }
            guard let range = token.range, !range.isEmpty else { continue }
            let labelID = predicted[index]
            guard let rawLabel = config.id2label[labelID] else { continue }
            let confidence = index < confidences.count ? confidences[index] : 1.0

            let effectiveLabel: String
            if token.isContinuation {
                effectiveLabel = currentWordEntity.map { "I-\($0)" } ?? "O"
            } else {
                effectiveLabel = rawLabel
                currentWordEntity = BIOSpanDecoder.entityName(from: rawLabel)
            }

            tokenRanges.append(range)
            labels.append(effectiveLabel)
            tokenConfidences.append(confidence)
        }

        let spans = BIOSpanDecoder.decode(
            text: text,
            tokenRanges: tokenRanges,
            labels: labels,
            confidences: tokenConfidences
        )
        return spans.compactMap { span -> SensitiveEntity? in
            guard span.confidence >= minConfidence else { return nil }
            guard let entityType = NERLabelMapper.defaultEntityType(for: span.label) else {
                return nil
            }
            guard options.enabledTypes.contains(entityType) else { return nil }
            return SensitiveEntity(
                type: entityType,
                range: span.range,
                value: span.value,
                confidence: span.confidence,
                source: .ai
            )
        }
    }

    /// Adjacent windows see the same entity differently truncated at their edges, producing
    /// overlapping (not just identical) spans. Merge same-type overlaps into one covering span;
    /// cross-type overlaps are left for the later `OverlapResolver`.
    static func mergeWindowOverlaps(_ entities: [SensitiveEntity], in text: String) -> [SensitiveEntity] {
        var merged: [SensitiveEntity] = []
        for (_, group) in Dictionary(grouping: entities, by: \.type) {
            let sorted = group.sorted { $0.range.lowerBound < $1.range.lowerBound }
            var current: SensitiveEntity?
            for entity in sorted {
                guard let open = current, open.range.overlaps(entity.range) else {
                    if let open = current { merged.append(open) }
                    current = entity
                    continue
                }
                let lowerBound = min(open.range.lowerBound, entity.range.lowerBound)
                let upperBound = max(open.range.upperBound, entity.range.upperBound)
                let range = lowerBound..<upperBound
                current = SensitiveEntity(
                    id: open.id,
                    type: open.type,
                    range: range,
                    value: String(text[range]),
                    // The window that saw the entity whole is the more trustworthy one.
                    confidence: max(open.confidence, entity.confidence),
                    source: open.source
                )
            }
            if let open = current { merged.append(open) }
        }
        return merged.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
