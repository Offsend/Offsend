import DetectionCore
import Foundation

public protocol PDFRedactionPlanBuilding: Sendable {
    func buildPlan(
        analysis: DocumentAnalysisResult,
        pdfData: Data,
        selectedEntityIDs: Set<UUID>,
        manualRegions: [PDFRedactionRegion]
    ) throws -> PDFRedactionPlan
}

public struct PDFRedactionPlanBuilder: PDFRedactionPlanBuilding {
    private let regionResolver: PDFRedactionRegionResolving

    public init(regionResolver: PDFRedactionRegionResolving = PDFRedactionRegionResolver()) {
        self.regionResolver = regionResolver
    }

    public func buildPlan(
        analysis: DocumentAnalysisResult,
        pdfData: Data,
        selectedEntityIDs: Set<UUID>,
        manualRegions: [PDFRedactionRegion]
    ) throws -> PDFRedactionPlan {
        guard analysis.extracted.format == .pdf else {
            throw PDFRedactionError.unsupportedFormat
        }

        let selectedEntities = analysis.detection.entities.filter { selectedEntityIDs.contains($0.id) }
        let autoRegions = try regionResolver.resolveRegions(
            in: pdfData,
            entities: selectedEntities,
            padding: PDFRedactionDefaults.regionPadding
        )

        let resolvedValues = Set(
            autoRegions.compactMap { region -> String? in
                guard case let .detected(_, value) = region.source else { return nil }
                return value
            }
        )
        _ = selectedEntities.uniqueByValue()
            .map(\.value)
            .filter { !resolvedValues.contains($0) }

        return Self.composePlan(
            selectedEntityIDs: selectedEntityIDs,
            manualRegions: manualRegions,
            resolvedAutoRegions: autoRegions,
            selectedEntities: selectedEntities
        )
    }

    public static func composePlan(
        selectedEntityIDs: Set<UUID>,
        manualRegions: [PDFRedactionRegion],
        resolvedAutoRegions: [PDFRedactionRegion],
        selectedEntities: [SensitiveEntity]
    ) -> PDFRedactionPlan {
        let autoRegions = resolvedAutoRegions.filter { region in
            guard case let .detected(entityID, _) = region.source else { return false }
            return selectedEntityIDs.contains(entityID)
        }

        let resolvedValues = Set(
            autoRegions.compactMap { region -> String? in
                guard case let .detected(_, value) = region.source else { return nil }
                return value
            }
        )
        let unresolvedValues = selectedEntities.uniqueByValue()
            .map(\.value)
            .filter { !resolvedValues.contains($0) }

        let mergedRegions = mergeOverlapping(autoRegions + manualRegions)
        return PDFRedactionPlan(regions: mergedRegions, unresolvedValues: unresolvedValues)
    }

    /// Drops regions fully contained within another region on the same page (e.g. a manual box
    /// covering an auto-detected one). Exact duplicates collapse to their first occurrence.
    /// Returns the survivors in reading order.
    private static func mergeOverlapping(_ regions: [PDFRedactionRegion]) -> [PDFRedactionRegion] {
        let survivors = regions.enumerated().filter { index, candidate in
            !regions.enumerated().contains { otherIndex, other in
                guard otherIndex != index, other.pageIndex == candidate.pageIndex else { return false }
                guard other.bounds.contains(candidate.bounds) else { return false }
                // Strictly larger region always wins; equal duplicates defer to the earlier one.
                return other.bounds != candidate.bounds || otherIndex < index
            }
        }.map(\.element)

        return survivors.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
            if lhs.bounds.minY != rhs.bounds.minY { return lhs.bounds.minY > rhs.bounds.minY }
            return lhs.bounds.minX < rhs.bounds.minX
        }
    }
}
