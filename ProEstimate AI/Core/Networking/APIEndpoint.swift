import Foundation

/// Defines all API endpoints as a type-safe enum with computed properties
/// for path, HTTP method, request body, and auth requirements.
/// Adding a new endpoint is a single enum case — no scattered string URLs.
enum APIEndpoint: Sendable {
    // MARK: - Auth
    case authLogin(email: String, password: String)
    case authSignup(email: String, password: String, fullName: String, companyName: String)
    case authAppleSignIn(body: Encodable & Sendable)
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
        case .getClient(let id): return "/clients/\(id)"
        case .createClient: return "/clients"
        case .updateClient(let id, _): return "/clients/\(id)"
        case .deleteClient(let id): return "/clients/\(id)"

        // Projects
        case .listProjects: return "/projects"
        case .getProject(let id): return "/projects/\(id)"
        case .createProject: return "/projects"
        case .updateProject(let id, _): return "/projects/\(id)"
        case .deleteProject(let id): return "/projects/\(id)"

        // Assets
        case .listAssets(let projectId): return "/projects/\(projectId)/assets"
        case .uploadAsset(let projectId, _): return "/projects/\(projectId)/assets"
        case .deleteAsset(let id): return "/assets/\(id)"

        // AI Generations
        case .listGenerations(let projectId): return "/projects/\(projectId)/generations"
        case .createGeneration(let projectId, _): return "/projects/\(projectId)/generations"
        case .getGeneration(let id): return "/generations/\(id)"

        // Material Suggestions
        case .listMaterialSuggestions(let generationId): return "/generations/\(generationId)/materials"
        case .updateMaterialSelection(let id, _): return "/materials/\(id)"

        // Estimates
        case .listEstimates: return "/estimates"
        case .getEstimate(let id): return "/estimates/\(id)"
        case .createEstimate: return "/estimates"
        case .generateAIEstimate: return "/estimates/generate"
        case .updateEstimate(let id, _): return "/estimates/\(id)"
        case .deleteEstimate(let id): return "/estimates/\(id)"

        // Estimate Line Items
        case .listEstimateLineItems(let estimateId): return "/estimates/\(estimateId)/line-items"
        case .createEstimateLineItem(let estimateId, _): return "/estimates/\(estimateId)/line-items"
        case .updateEstimateLineItem(let id, _): return "/estimate-line-items/\(id)"
        case .deleteEstimateLineItem(let id): return "/estimate-line-items/\(id)"

        // Proposals
        case .getProposal(let id): return "/proposals/\(id)"
        case .createProposal: return "/proposals"
        case .sendProposal(let id): return "/proposals/\(id)/send"
        case .listProposals: return "/proposals"

        // Pricing Profiles
        case .listPricingProfiles: return "/pricing-profiles"
        case .getPricingProfile(let id): return "/pricing-profiles/\(id)"
        case .createPricingProfile: return "/pricing-profiles"
        case .updatePricingProfile(let id, _): return "/pricing-profiles/\(id)"
        case .deletePricingProfile(let id): return "/pricing-profiles/\(id)"

        // Labor Rate Rules
        case .listLaborRateRules(let profileId): return "/pricing-profiles/\(profileId)/labor-rates"
        case .createLaborRateRule(let profileId, _): return "/pricing-profiles/\(profileId)/labor-rates"
        case .updateLaborRateRule(let id, _): return "/labor-rates/\(id)"
        case .deleteLaborRateRule(let id): return "/labor-rates/\(id)"

        // Activity Log
        case .listActivityLog(let projectId, _): return "/projects/\(projectId)/activity"

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
        }
    }

    /// The HTTP method for this endpoint.
    var method: HTTPMethod {
        switch self {
        case .authLogin, .authSignup, .authAppleSignIn, .authRefreshToken, .authLogout,
             .authForgotPassword,
             .uploadCompanyLogo,
             .createClient, .createProject, .uploadAsset, .createGeneration,
             .createEstimate, .generateAIEstimate, .createEstimateLineItem,
             .createProposal, .sendProposal,
             .createPricingProfile, .createLaborRateRule,
             .createPurchaseAttempt, .syncTransaction, .restorePurchases,
             .checkUsage:
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
        case .authLogin, .authSignup, .authAppleSignIn, .authRefreshToken, .authForgotPassword:
            return false
        default:
            return true
        }
    }

    /// Optional query parameters appended to the URL.
    var queryItems: [URLQueryItem]? {
        switch self {
        case .listClients(let cursor):
            return cursor.map { [URLQueryItem(name: "cursor", value: $0)] }
        case .listProjects(let cursor):
            return cursor.map { [URLQueryItem(name: "cursor", value: $0)] }
        case .listEstimates(let projectId):
            return projectId.map { [URLQueryItem(name: "project_id", value: $0)] }
        case .listProposals(let projectId):
            return projectId.map { [URLQueryItem(name: "project_id", value: $0)] }
        case .listActivityLog(_, let cursor):
            return cursor.map { [URLQueryItem(name: "cursor", value: $0)] }
        case .searchMaterialsPricing(let query, let zipCode, let sort, let maxResults):
            var items = [URLQueryItem(name: "query", value: query)]
            if let zipCode { items.append(URLQueryItem(name: "zip_code", value: zipCode)) }
            if let sort { items.append(URLQueryItem(name: "sort", value: sort)) }
            if let maxResults { items.append(URLQueryItem(name: "max_results", value: String(maxResults))) }
            return items
        case .projectMaterialsPricing(let projectType, let zipCode):
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
        case .authLogin(let email, let password):
            return LoginBody(email: email, password: password)
        case .authSignup(let email, let password, let fullName, let companyName):
            return SignupBody(email: email, password: password, fullName: fullName, companyName: companyName)
        case .authAppleSignIn(let body):
            return body
        case .authRefreshToken(let refreshToken):
            return RefreshBody(refreshToken: refreshToken)
        case .authForgotPassword(let email):
            return ForgotPasswordBody(email: email)
        case .updateCompany(let body),
             .uploadCompanyLogo(let body),
             .createClient(let body), .updateClient(_, let body),
             .createProject(let body), .updateProject(_, let body),
             .uploadAsset(_, let body),
             .createGeneration(_, let body),
             .createEstimate(let body), .generateAIEstimate(let body),
             .updateEstimate(_, let body),
             .createEstimateLineItem(_, let body), .updateEstimateLineItem(_, let body),
             .createProposal(let body),
             .createPricingProfile(let body), .updatePricingProfile(_, let body),
             .createLaborRateRule(_, let body), .updateLaborRateRule(_, let body),
             .createPurchaseAttempt(let body), .syncTransaction(let body),
             .restorePurchases(let body), .checkUsage(let body):
            return body
        case .updateMaterialSelection(_, let isSelected):
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
