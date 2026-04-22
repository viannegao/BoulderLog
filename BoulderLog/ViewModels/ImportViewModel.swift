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
        print("[BoulderLog] processSelection started, identifier: \(assetIdentifier)")
        state = .processing
        currentAssetIdentifier = assetIdentifier
        do {
            print("[BoulderLog] calling analyze...")
            let result = try await withTimeout(seconds: 30) {
                try await ImportPipeline.analyze(assetIdentifier: assetIdentifier, context: context)
            }
            print("[BoulderLog] analyze returned: \(result)")
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
    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let workTask = Task { @MainActor in try await operation() }
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(seconds))
            workTask.cancel()
        }
        do {
            let result = try await workTask.value
            timeoutTask.cancel()
            return result
        } catch {
            timeoutTask.cancel()
            throw error
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
