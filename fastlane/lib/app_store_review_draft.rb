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
    # Items determine what will be submitted. appStoreVersionForReview is
    # informational and may still point at a previous version in an empty
    # draft; pinned deliver reuses such drafts and adds the target as an item.
    items = api.call(:get, "reviewSubmissions/#{id}/items?limit=200")
    unless items.fetch("data").empty? && items.dig("links", "next").nil?
      raise "Review draft contains existing or unverified items; fastlane must not reuse it"
    end
    linked_version = draft.dig("relationships", "appStoreVersionForReview", "data")
    linked_type = linked_version.is_a?(Hash) ? linked_version["type"] : nil
    linked_id = linked_version.is_a?(Hash) ? linked_version["id"] : nil
    log.call("Reusing empty READY_FOR_REVIEW draft=#{id} app=#{app_id} platform=#{platform} targetVersion=#{version_id} informationalVersionType=#{linked_type.inspect} informationalVersionId=#{linked_id.inspect} items=0")
    id
  end
end
