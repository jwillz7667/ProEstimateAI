import Foundation

/// Defines all API endpoints as a type-safe enum with computed properties
/// for path, HTTP method, request body, and auth requirements.
/// Adding a new endpoint is a single enum case — no scattered string URLs.
enum APIEndpoint: Sendable {
    // MARK: - Auth

    case authLogin(email: String, password: String)
    case authSignup(email: String, password: String, fullName: String, companyName: String)
    case authAppleSignIn(body: Encodable & Sendable)
    /// Google OAuth sign-in. Body carries the ID token Google issued for
    /// the iOS Client; backend verifies + provisions / logs the user in.
    case authGoogleSignIn(body: Encodable & Sendable)
    case authRefreshToken(refreshToken: String)
    case authLogout
    case authForgotPassword(email: String)

    // MARK: - User / Company

    case getMe
    case deleteMe
    case getCompany
    case updateCompany(body: Encodable & Sendable)
    case uploadCompanyLogo(body: Encodable & Sendable)
    case deleteCompanyLogo

    // MARK: - Clients

    case listClients(cursor: String?)
    case getClient(id: String)
    case createClient(body: Encodable & Sendable)
    case updateClient(id: String, body: Encodable & Sendable)
    case deleteClient(id: String)

    // MARK: - Projects

    case listProjects(cursor: String?)
    case getProject(id: String)
    case createProject(body: Encodable & Sendable)
    case updateProject(id: String, body: Encodable & Sendable)
    case deleteProject(id: String)

    // MARK: - Assets

    case listAssets(projectId: String)
    case uploadAsset(projectId: String, body: Encodable & Sendable)
    case deleteAsset(id: String)

    // MARK: - AI Generations

    case listGenerations(projectId: String)
    case createGeneration(projectId: String, body: Encodable & Sendable)
    case getGeneration(id: String)

    // MARK: - Material Suggestions

    case listMaterialSuggestions(generationId: String)
    case updateMaterialSelection(id: String, isSelected: Bool)

    // MARK: - Estimates

    case listEstimates(projectId: String?)
    case getEstimate(id: String)
    case createEstimate(body: Encodable & Sendable)
    /// AI-generate a complete estimate from the project's materials + the
    /// company's branding and defaults. Body: `{ project_id: String }`.
    case generateAIEstimate(body: Encodable & Sendable)
    case updateEstimate(id: String, body: Encodable & Sendable)
    case deleteEstimate(id: String)

    // MARK: - Estimate Line Items

    case listEstimateLineItems(estimateId: String)
    case createEstimateLineItem(estimateId: String, body: Encodable & Sendable)
    case updateEstimateLineItem(id: String, body: Encodable & Sendable)
    case deleteEstimateLineItem(id: String)

    // MARK: - Proposals

    case getProposal(id: String)
    case createProposal(body: Encodable & Sendable)
    case sendProposal(id: String)
    case listProposals(projectId: String?)

    // MARK: - Pricing Profiles

    case listPricingProfiles
    case getPricingProfile(id: String)
    case createPricingProfile(body: Encodable & Sendable)
    case updatePricingProfile(id: String, body: Encodable & Sendable)
    case deletePricingProfile(id: String)

    // MARK: - Labor Rate Rules

    case listLaborRateRules(profileId: String)
    case createLaborRateRule(profileId: String, body: Encodable & Sendable)
    case updateLaborRateRule(id: String, body: Encodable & Sendable)
    case deleteLaborRateRule(id: String)

    // MARK: - Activity Log

    case listActivityLog(projectId: String, cursor: String?)

    // MARK: - Commerce

    case getCommerceProducts
    case getEntitlement
    case createPurchaseAttempt(body: Encodable & Sendable)
    case syncTransaction(body: Encodable & Sendable)
    case restorePurchases(body: Encodable & Sendable)

    // MARK: - Usage

    case getUsage
    case checkUsage(body: Encodable & Sendable)

    // MARK: - Dashboard

    case getDashboardSummary

    // MARK: - Materials Pricing

    case searchMaterialsPricing(query: String, zipCode: String?, sort: String?, maxResults: Int?)
    case projectMaterialsPricing(projectType: String, zipCode: String?)

    // MARK: - Property Maps

    /// Geocode a free-form address to lat/lng + ZIP / city / region.
    case mapsGeocode(body: Encodable & Sendable)
    /// Compute lawn polygon area in sq ft. Optional `project_id` writes
    /// the result back to the project (lawn_area_sq_ft + lat/lng).
    case mapsLawnArea(body: Encodable & Sendable)
    /// Roof scouting via Google Solar API. Accepts address OR lat/lng.
    /// Optional `project_id` writes total roof area back to the project.
    case mapsRoofScouting(body: Encodable & Sendable)
}

// MARK: - Computed Properties

extension APIEndpoint {
    /// The URL path relative to the API base URL.
    var path: String {
        switch self {
        // Auth
        case .authLogin: return "/auth/login"
        case .authSignup: return "/auth/signup"
        case .authAppleSignIn: return "/auth/apple-signin"
        case .authGoogleSignIn: return "/auth/google-signin"
        case .authRefreshToken: return "/auth/refresh"
        case .authLogout: return "/auth/logout"
        case .authForgotPassword: return "/auth/forgot-password"
        // User / Company
        case .getMe: return "/users/me"
        case .deleteMe: return "/users/me"
        case .getCompany: return "/companies/me"
        case .updateCompany: return "/companies/me"
        case .uploadCompanyLogo: return "/companies/me/logo"
        case .deleteCompanyLogo: return "/companies/me/logo"
        // Clients
        case .listClients: return "/clients"
        case let .getClient(id): return "/clients/\(id)"
        case .createClient: return "/clients"
        case let .updateClient(id, _): return "/clients/\(id)"
        case let .deleteClient(id): return "/clients/\(id)"
        // Projects
        case .listProjects: return "/projects"
        case let .getProject(id): return "/projects/\(id)"
        case .createProject: return "/projects"
        case let .updateProject(id, _): return "/projects/\(id)"
        case let .deleteProject(id): return "/projects/\(id)"
        // Assets
        case let .listAssets(projectId): return "/projects/\(projectId)/assets"
        case let .uploadAsset(projectId, _): return "/projects/\(projectId)/assets"
        case let .deleteAsset(id): return "/assets/\(id)"
        // AI Generations
        case let .listGenerations(projectId): return "/projects/\(projectId)/generations"
        case let .createGeneration(projectId, _): return "/projects/\(projectId)/generations"
        case let .getGeneration(id): return "/generations/\(id)"
        // Material Suggestions
        case let .listMaterialSuggestions(generationId): return "/generations/\(generationId)/materials"
        case let .updateMaterialSelection(id, _): return "/materials/\(id)"
        // Estimates
        case .listEstimates: return "/estimates"
        case let .getEstimate(id): return "/estimates/\(id)"
        case .createEstimate: return "/estimates"
        case .generateAIEstimate: return "/estimates/generate"
        case let .updateEstimate(id, _): return "/estimates/\(id)"
        case let .deleteEstimate(id): return "/estimates/\(id)"
        // Estimate Line Items
        case let .listEstimateLineItems(estimateId): return "/estimates/\(estimateId)/line-items"
        case let .createEstimateLineItem(estimateId, _): return "/estimates/\(estimateId)/line-items"
        case let .updateEstimateLineItem(id, _): return "/estimate-line-items/\(id)"
        case let .deleteEstimateLineItem(id): return "/estimate-line-items/\(id)"
        // Proposals
        case let .getProposal(id): return "/proposals/\(id)"
        case .createProposal: return "/proposals"
        case let .sendProposal(id): return "/proposals/\(id)/send"
        case .listProposals: return "/proposals"
        // Pricing Profiles
        case .listPricingProfiles: return "/pricing-profiles"
        case let .getPricingProfile(id): return "/pricing-profiles/\(id)"
        case .createPricingProfile: return "/pricing-profiles"
        case let .updatePricingProfile(id, _): return "/pricing-profiles/\(id)"
        case let .deletePricingProfile(id): return "/pricing-profiles/\(id)"
        // Labor Rate Rules
        case let .listLaborRateRules(profileId): return "/pricing-profiles/\(profileId)/labor-rates"
        case let .createLaborRateRule(profileId, _): return "/pricing-profiles/\(profileId)/labor-rates"
        case let .updateLaborRateRule(id, _): return "/labor-rates/\(id)"
        case let .deleteLaborRateRule(id): return "/labor-rates/\(id)"
        // Activity Log
        case let .listActivityLog(projectId, _): return "/projects/\(projectId)/activity"
        // Commerce
        case .getCommerceProducts: return "/commerce/products"
        case .getEntitlement: return "/commerce/entitlement"
        case .createPurchaseAttempt: return "/commerce/purchase-attempt"
        case .syncTransaction: return "/commerce/transactions/sync"
        case .restorePurchases: return "/commerce/restore"
        // Usage
        case .getUsage: return "/usage"
        case .checkUsage: return "/usage/check"
        // Dashboard
        case .getDashboardSummary: return "/dashboard/summary"
        // Materials Pricing
        case .searchMaterialsPricing: return "/materials-pricing/search"
        case .projectMaterialsPricing: return "/materials-pricing/project"
        // Property Maps
        case .mapsGeocode: return "/maps/geocode"
        case .mapsLawnArea: return "/maps/lawn-area"
        case .mapsRoofScouting: return "/maps/roof-scouting"
        }
    }

    /// The HTTP method for this endpoint.
    var method: HTTPMethod {
        switch self {
        case .authLogin, .authSignup, .authAppleSignIn, .authGoogleSignIn,
             .authRefreshToken, .authLogout,
             .authForgotPassword,
             .uploadCompanyLogo,
             .createClient, .createProject, .uploadAsset, .createGeneration,
             .createEstimate, .generateAIEstimate, .createEstimateLineItem,
             .createProposal, .sendProposal,
             .createPricingProfile, .createLaborRateRule,
             .createPurchaseAttempt, .syncTransaction, .restorePurchases,
             .checkUsage,
             .mapsGeocode, .mapsLawnArea, .mapsRoofScouting:
            return .post

        case .updateCompany, .updateClient, .updateProject,
             .updateMaterialSelection, .updateEstimate, .updateEstimateLineItem,
             .updatePricingProfile, .updateLaborRateRule:
            return .patch

        case .deleteMe,
             .deleteCompanyLogo,
             .deleteClient, .deleteProject, .deleteAsset,
             .deleteEstimate, .deleteEstimateLineItem,
             .deletePricingProfile, .deleteLaborRateRule:
            return .delete

        default:
            return .get
        }
    }

    /// Whether this endpoint requires an Authorization header with a bearer token.
    var requiresAuth: Bool {
        switch self {
        case .authLogin, .authSignup, .authAppleSignIn, .authGoogleSignIn,
             .authRefreshToken, .authForgotPassword:
            return false
        default:
            return true
        }
    }

    /// Optional query parameters appended to the URL.
    var queryItems: [URLQueryItem]? {
        switch self {
        case let .listClients(cursor):
            return cursor.map { [URLQueryItem(name: "cursor", value: $0)] }
        case let .listProjects(cursor):
            return cursor.map { [URLQueryItem(name: "cursor", value: $0)] }
        case let .listEstimates(projectId):
            return projectId.map { [URLQueryItem(name: "project_id", value: $0)] }
        case let .listProposals(projectId):
            return projectId.map { [URLQueryItem(name: "project_id", value: $0)] }
        case let .listActivityLog(_, cursor):
            return cursor.map { [URLQueryItem(name: "cursor", value: $0)] }
        case let .searchMaterialsPricing(query, zipCode, sort, maxResults):
            var items = [URLQueryItem(name: "query", value: query)]
            if let zipCode { items.append(URLQueryItem(name: "zip_code", value: zipCode)) }
            if let sort { items.append(URLQueryItem(name: "sort", value: sort)) }
            if let maxResults { items.append(URLQueryItem(name: "max_results", value: String(maxResults))) }
            return items
        case let .projectMaterialsPricing(projectType, zipCode):
            var items = [URLQueryItem(name: "project_type", value: projectType)]
            if let zipCode { items.append(URLQueryItem(name: "zip_code", value: zipCode)) }
            return items
        default:
            return nil
        }
    }

    /// The request body, if any. Callers encode this into the URLRequest.
    var body: (any Encodable & Sendable)? {
        switch self {
        case let .authLogin(email, password):
            return LoginBody(email: email, password: password)
        case let .authSignup(email, password, fullName, companyName):
            return SignupBody(email: email, password: password, fullName: fullName, companyName: companyName)
        case let .authAppleSignIn(body):
            return body
        case let .authGoogleSignIn(body):
            return body
        case let .authRefreshToken(refreshToken):
            return RefreshBody(refreshToken: refreshToken)
        case let .authForgotPassword(email):
            return ForgotPasswordBody(email: email)
        case let .updateCompany(body),
             let .uploadCompanyLogo(body),
             let .createClient(body), let .updateClient(_, body),
             let .createProject(body), let .updateProject(_, body),
             let .uploadAsset(_, body),
             let .createGeneration(_, body),
             let .createEstimate(body), let .generateAIEstimate(body),
             let .updateEstimate(_, body),
             let .createEstimateLineItem(_, body), let .updateEstimateLineItem(_, body),
             let .createProposal(body),
             let .createPricingProfile(body), let .updatePricingProfile(_, body),
             let .createLaborRateRule(_, body), let .updateLaborRateRule(_, body),
             let .createPurchaseAttempt(body), let .syncTransaction(body),
             let .restorePurchases(body), let .checkUsage(body),
             let .mapsGeocode(body), let .mapsLawnArea(body),
             let .mapsRoofScouting(body):
            return body
        case let .updateMaterialSelection(_, isSelected):
            return MaterialSelectionBody(isSelected: isSelected)
        default:
            return nil
        }
    }
}

// MARK: - HTTP Method

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - Internal Body Types

/// Login request body.
private struct LoginBody: Encodable, Sendable {
    let email: String
    let password: String
}

/// Signup request body.
private struct SignupBody: Encodable, Sendable {
    let email: String
    let password: String
    let fullName: String
    let companyName: String

    enum CodingKeys: String, CodingKey {
        case email, password
        case fullName = "full_name"
        case companyName = "company_name"
    }
}

/// Token refresh request body.
private struct RefreshBody: Encodable, Sendable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

/// Forgot password request body.
private struct ForgotPasswordBody: Encodable, Sendable {
    let email: String
}

/// Material selection toggle body.
private struct MaterialSelectionBody: Encodable, Sendable {
    let isSelected: Bool

    enum CodingKeys: String, CodingKey {
        case isSelected = "is_selected"
    }
}
