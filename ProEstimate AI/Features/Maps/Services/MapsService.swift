import CoreLocation
import Foundation

protocol MapsServiceProtocol: Sendable {
    /// Resolve an address to a canonical `GeocodeResult`.
    func geocode(address: String) async throws -> GeocodeResult

    /// Compute the area of a polygon (lat/lng vertices) in sq ft. When
    /// `projectId` is non-nil, the result is also persisted on the
    /// project (lawn_area_sq_ft + property_latitude/longitude).
    func measureLawn(
        polygon: [CLLocationCoordinate2D],
        projectId: String?
    ) async throws -> LawnAreaResult

    /// Run the Solar API roof scouting flow. Provide either an address
    /// (we'll geocode internally) or an explicit lat/lng. When
    /// `projectId` is non-nil, the result is persisted on the project.
    func scoutRoof(
        address: String?,
        coordinate: CLLocationCoordinate2D?,
        projectId: String?
    ) async throws -> RoofScoutingResult
}

// MARK: - Live Implementation

final class LiveMapsService: MapsServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    func geocode(address: String) async throws -> GeocodeResult {
        let body = GeocodeBody(address: address)
        return try await apiClient.request(.mapsGeocode(body: body))
    }

    func measureLawn(
        polygon: [CLLocationCoordinate2D],
        projectId: String?
    ) async throws -> LawnAreaResult {
        let body = LawnAreaBody(
            polygon: polygon.map(LatLngBody.init(coordinate:)),
            projectId: projectId
        )
        return try await apiClient.request(.mapsLawnArea(body: body))
    }

    func scoutRoof(
        address: String?,
        coordinate: CLLocationCoordinate2D?,
        projectId: String?
    ) async throws -> RoofScoutingResult {
        let body = RoofScoutingBody(
            address: address,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            projectId: projectId
        )
        return try await apiClient.request(.mapsRoofScouting(body: body))
    }
}

// MARK: - Mock

final class MockMapsService: MapsServiceProtocol {
    func geocode(address: String) async throws -> GeocodeResult {
        try await Task.sleep(nanoseconds: 300_000_000)
        return GeocodeResult(
            formattedAddress: address,
            latitude: 44.9778,
            longitude: -93.2650,
            postalCode: "55401",
            city: "Minneapolis",
            region: "Minnesota"
        )
    }

    func measureLawn(
        polygon: [CLLocationCoordinate2D],
        projectId _: String?
    ) async throws -> LawnAreaResult {
        try await Task.sleep(nanoseconds: 200_000_000)
        return LawnAreaResult(
            areaSqMeters: 920,
            areaSqFt: 9902,
            centroidLatitude: polygon.first?.latitude ?? 0,
            centroidLongitude: polygon.first?.longitude ?? 0
        )
    }

    func scoutRoof(
        address: String?,
        coordinate _: CLLocationCoordinate2D?,
        projectId _: String?
    ) async throws -> RoofScoutingResult {
        try await Task.sleep(nanoseconds: 500_000_000)
        return RoofScoutingResult(
            buildingLatitude: 44.9778,
            buildingLongitude: -93.2650,
            postalCode: "55401",
            totalRoofAreaSqFt: 2240,
            segments: [
                RoofSegment(
                    index: 1,
                    pitchDegrees: 22,
                    azimuthDegrees: 180,
                    areaSqMeters: 104,
                    areaSqFt: 1120,
                    centerLatitude: 44.9778,
                    centerLongitude: -93.2650
                ),
                RoofSegment(
                    index: 2,
                    pitchDegrees: 22,
                    azimuthDegrees: 0,
                    areaSqMeters: 104,
                    areaSqFt: 1120,
                    centerLatitude: 44.9779,
                    centerLongitude: -93.2650
                ),
            ],
            imageryDate: "2024-08-12T00:00:00Z",
            imageryQuality: "HIGH",
            resolvedAddress: address
        )
    }
}

// MARK: - Request Bodies (snake_case via APIClient encoder)

private struct GeocodeBody: Encodable, Sendable {
    let address: String
}

private struct LatLngBody: Encodable, Sendable {
    let latitude: Double
    let longitude: Double

    init(coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}

private struct LawnAreaBody: Encodable, Sendable {
    let polygon: [LatLngBody]
    let projectId: String?
}

private struct RoofScoutingBody: Encodable, Sendable {
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let projectId: String?
}
