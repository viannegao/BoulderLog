import SwiftData
import Observation

enum ImportState {
    case idle
    case processing
    case matched(route: Route, confidence: Float, descriptor: RouteDescriptor)
    case ambiguous(route: Route, confidence: Float, descriptor: RouteDescriptor)
    case newRoute(descriptor: RouteDescriptor)
    case noHoldsDetected(descriptor: RouteDescriptor?)
    case duplicate
    case error(String)
}

@Observable
final class ImportViewModel {
    var state: ImportState = .idle
    var isSend = false
    var notes = ""
    var currentAssetIdentifier: String?

    @MainActor
    func processSelection(assetIdentifier: String, context: ModelContext) async {
        state = .processing
        let identifier = assetIdentifier
        currentAssetIdentifier = identifier
        do {
            let result = try await ImportPipeline.analyze(assetIdentifier: identifier, context: context)
            switch result {
            case .matched(let route, let confidence, let descriptor):
                state = confidence >= 0.7
                    ? .matched(route: route, confidence: confidence, descriptor: descriptor)
                    : .ambiguous(route: route, confidence: confidence, descriptor: descriptor)
            case .newRoute(let descriptor):
                state = .newRoute(descriptor: descriptor)
            case .noHoldsDetected:
                state = .noHoldsDetected(descriptor: nil)
            case .duplicate(_):
                state = .duplicate
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    @MainActor
    func confirm(assetIdentifier: String, route: Route, descriptor: RouteDescriptor,
                 context: ModelContext) -> Bool {
        do {
            try ImportPipeline.save(assetIdentifier: assetIdentifier, to: route,
                                    isSend: isSend, notes: notes,
                                    descriptor: descriptor, context: context)
            reset()
            return true
        } catch {
            state = .error(error.localizedDescription)
            return false
        }
    }

    @MainActor
    func confirmNewRoute(assetIdentifier: String, descriptor: RouteDescriptor,
                         context: ModelContext) -> Bool {
        do {
            try ImportPipeline.saveAsNewRoute(assetIdentifier: assetIdentifier,
                                              descriptor: descriptor,
                                              isSend: isSend, notes: notes,
                                              context: context)
            reset()
            return true
        } catch {
            state = .error(error.localizedDescription)
            return false
        }
    }

    @MainActor
    private func reset() {
        currentAssetIdentifier = nil
        state = .idle
        isSend = false
        notes = ""
    }
}
