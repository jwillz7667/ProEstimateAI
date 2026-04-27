import CoreLocation
import Foundation

// MARK: - Geocode

struct GeocodeResult: Codable, Hashable, Sendable {
    let formattedAddress: String
    let latitude: Double
    let longitude: Double
    let postalCode: String?
    let city: String?
    let region: String?

    enum CodingKeys: String, CodingKey {
        case formattedAddress = "formatted_address"
        case latitude
        case longitude
        case postalCode = "postal_code"
        case city
        case region
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Lawn Area

struct LawnAreaResult: Codable, Hashable, Sendable {
    let areaSqMeters: Double
    let areaSqFt: Double
    let centroidLatitude: Double
    let centroidLongitude: Double

    enum CodingKeys: String, CodingKey {
        case areaSqMeters = "area_sq_meters"
        case areaSqFt = "area_sq_ft"
        case centroidLatitude = "centroid_latitude"
        case centroidLongitude = "centroid_longitude"
    }
}

// MARK: - Roof Scouting

struct RoofScoutingResult: Codable, Hashable, Sendable {
    let buildingLatitude: Double
    let buildingLongitude: Double
    let postalCode: String?
    let totalRoofAreaSqFt: Double
    let segments: [RoofSegment]
    let imageryDate: String?
    let imageryQuality: String?
    let resolvedAddress: String?

    enum CodingKeys: String, CodingKey {
        case buildingLatitude = "building_latitude"
        case buildingLongitude = "building_longitude"
        case postalCode = "postal_code"
        case totalRoofAreaSqFt = "total_roof_area_sq_ft"
        case segments
        case imageryDate = "imagery_date"
        case imageryQuality = "imagery_quality"
        case resolvedAddress = "resolved_address"
    }

    var buildingCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: buildingLatitude, longitude: buildingLongitude)
    }

    /// Convert total roof area to "squares" (100 sq ft each) — the unit
    /// every roofing material is sold in.
    var totalSquares: Double {
        totalRoofAreaSqFt / 100
    }
}

struct RoofSegment: Codable, Hashable, Identifiable, Sendable {
    let index: Int
    let pitchDegrees: Double
    let azimuthDegrees: Double
    let areaSqMeters: Double
    let areaSqFt: Double
    let centerLatitude: Double
    let centerLongitude: Double

    var id: Int {
        index
    }

    enum CodingKeys: String, CodingKey {
        case index
        case pitchDegrees = "pitch_degrees"
        case azimuthDegrees = "azimuth_degrees"
        case areaSqMeters = "area_sq_meters"
        case areaSqFt = "area_sq_ft"
        case centerLatitude = "center_latitude"
        case centerLongitude = "center_longitude"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    /// Closest cardinal direction the segment faces. Useful labels for
    /// roof reports ("South-facing rear plane, 22° pitch, 480 sq ft").
    var compassDirection: String {
        let normalized = (azimuthDegrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        switch normalized {
        case 337.5..., ..<22.5: return "N"
        case 22.5 ..< 67.5: return "NE"
        case 67.5 ..< 112.5: return "E"
        case 112.5 ..< 157.5: return "SE"
        case 157.5 ..< 202.5: return "S"
        case 202.5 ..< 247.5: return "SW"
        case 247.5 ..< 292.5: return "W"
        case 292.5 ..< 337.5: return "NW"
        default: return "?"
        }
    }
}
