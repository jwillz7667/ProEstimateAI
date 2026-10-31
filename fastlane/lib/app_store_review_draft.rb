require_relative "app_store_billing"

# Fastlane can reuse an empty, unsubmitted review draft. Never withdraw that
# draft: Apple rejects cancellation before a submission has been sent.
module AppStoreReviewDraft
  def self.validate(app_id:, platform:, version_id:, api:, log: ->(_message) {})
    submissions = AppStoreBilling.pages(
      "apps/#{app_id}/reviewSubmissions?filter[platform]=#{platform}&limit=200", api: api
    )
    blocked = submissions.select { |item| %w[WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES CANCELING].include?(item.dig("attributes", "state")) }
    raise "An App Store review submission is already in progress; no draft will be reused or withdrawn" unless blocked.empty?
    ready = submissions.select { |item| item.dig("attributes", "state") == "READY_FOR_REVIEW" }
    raise "Multiple READY_FOR_REVIEW drafts require manual review" if ready.length > 1
    return nil if ready.empty?

    id = ready.first.fetch("id")
    # The app-scoped collection proves ownership without relying on an
    # optional sparse app relationship in the single-resource response.
    draft = api.call(:get, "reviewSubmissions/#{id}?include=appStoreVersionForReview").fetch("data")
    unless draft["id"] == id && draft["type"] == "reviewSubmissions" &&
           draft.dig("attributes", "state") == "READY_FOR_REVIEW" &&
           draft.dig("attributes", "platform") == platform &&
           draft.dig("attributes", "submittedDate").nil?
      raise "Review draft app, platform or unsubmitted state does not match this release; no changes were made"
    end
    linked_version = draft.dig("relationships", "appStoreVersionForReview", "data")
    if linked_version && linked_version != { "type" => "appStoreVersions", "id" => version_id }
      raise "Review draft belongs to another App Store version; no changes were made"
    end

    # An empty draft has no version relationship when adding the version failed
    # validation. Deliver will add only the already validated target version.
    items = api.call(:get, "reviewSubmissions/#{id}/items?limit=200")
    unless items.fetch("data").empty? && items.dig("links", "next").nil?
      raise "Review draft contains existing or unverified items; fastlane must not reuse it"
    end
    log.call("Reusing empty READY_FOR_REVIEW draft=#{id} app=#{app_id} platform=#{platform} targetVersion=#{version_id}")
    id
  end
end
