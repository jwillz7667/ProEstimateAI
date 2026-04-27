import CoreLocation
import Foundation
import Observation

@Observable
final class RoofScoutingViewModel {
    private let service: MapsServiceProtocol
    private let projectId: String?

    /// User-entered address. Either this or an existing project lat/lng
    /// must be present before scouting can run.
    var addressInput: String = ""

    /// Pre-known project coordinate (e.g. from a prior lawn measurement
    /// or geocode on the project). When set, the scout call skips the
    /// geocode step and goes straight to Solar API.
    private let initialCoordinate: CLLocationCoordinate2D?

    var isScouting: Bool = false
    var result: RoofScoutingResult?
    var errorMessage: String?

    var hasResult: Bool {
        result != nil
    }

    init(
        projectId: String?,
        initialAddress: String? = nil,
        initialCoordinate: CLLocationCoordinate2D? = nil,
        service: MapsServiceProtocol = LiveMapsService()
    ) {
        self.projectId = projectId
        self.initialCoordinate = initialCoordinate
        self.service = service
        if let initialAddress {
            addressInput = initialAddress
        }
    }

    var canScout: Bool {
        let trimmed = addressInput.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty || initialCoordinate != nil
    }

    func scout() async {
        guard canScout else { return }
        isScouting = true
        errorMessage = nil
        result = nil
        defer { isScouting = false }

        let trimmed = addressInput.trimmingCharacters(in: .whitespaces)
        do {
            result = try await service.scoutRoof(
                address: trimmed.isEmpty ? nil : trimmed,
                coordinate: initialCoordinate,
                projectId: projectId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
