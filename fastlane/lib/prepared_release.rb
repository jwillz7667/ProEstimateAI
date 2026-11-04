require "json"
require "net/http"
require "uri"

# This helper can attach an already uploaded build to an editable draft. It
# deliberately has no App Review submission or release-request endpoint.
module PreparedRelease
  EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze

  def self.request(token:, method:, path:, body: nil)
    uri = URI("https://api.appstoreconnect.apple.com/v1/#{path}")
    klass = { get: Net::HTTP::Get, patch: Net::HTTP::Patch }.fetch(method)
    request = klass.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body) if body
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) { |http| http.request(request) }
    parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
    unless response.is_a?(Net::HTTPSuccess)
      details = parsed.fetch("errors", []).map { |error| error["detail"] }.join("; ")
      raise "App Store request failed (#{response.code}): #{details}"
    end
    parsed
  end

  def self.attach(app_id:, version_id:, marketing_version:, build_number:, api:)
    raise "An explicit numeric build number is required" unless build_number.to_s.match?(/\A[1-9]\d*\z/)
    version = api.call(:get, "appStoreVersions/#{version_id}").fetch("data")
    attributes = version.fetch("attributes")
    unless attributes["versionString"] == marketing_version && attributes["platform"] == "IOS" && EDITABLE_STATES.include?(attributes["appStoreState"])
      raise "Only the exact iOS version in an editable, unsubmitted state may receive a build"
    end

    query = URI.encode_www_form("filter[app]" => app_id, "filter[version]" => build_number.to_s, "include" => "preReleaseVersion", "limit" => "200")
    response = api.call(:get, "builds?#{query}")
    trains = response.fetch("included", []).select { |item| item["type"] == "preReleaseVersions" }.to_h { |item| [item.fetch("id"), item.fetch("attributes")] }
    builds = response.fetch("data").select do |build|
      train = trains[build.dig("relationships", "preReleaseVersion", "data", "id")]
      build.dig("attributes", "version") == build_number.to_s && train && train["version"] == marketing_version && train["platform"] == "IOS"
    end
    raise "Expected exactly one build #{build_number} for iOS #{marketing_version}" unless builds.length == 1
    build = builds.first
    unless build.dig("attributes", "processingState") == "VALID" && build.dig("attributes", "expired") == false
      raise "The selected build must finish processing as VALID and remain unexpired"
    end

    # Apple's documented build-linkage endpoint changes the selected binary;
    # releaseType MANUAL leaves the eventual release under human control.
    api.call(:patch, "appStoreVersions/#{version_id}", {
      data: { type: "appStoreVersions", id: version_id, attributes: { releaseType: "MANUAL" } }
    })
    api.call(:patch, "appStoreVersions/#{version_id}/relationships/build", {
      data: { type: "builds", id: build.fetch("id") }
    })
    linked = api.call(:get, "appStoreVersions/#{version_id}/relationships/build")
    updated = api.call(:get, "appStoreVersions/#{version_id}").fetch("data")
    unless linked.dig("data", "id") == build.fetch("id") && updated.dig("attributes", "releaseType") == "MANUAL" && EDITABLE_STATES.include?(updated.dig("attributes", "appStoreState"))
      raise "Build attachment readback did not match the selected build and manual draft state"
    end
    { version_id: version_id, version: marketing_version, build_id: build.fetch("id"), build: build_number.to_s, state: updated.dig("attributes", "appStoreState"), release_type: "MANUAL" }
  end
end
