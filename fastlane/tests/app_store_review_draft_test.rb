require_relative "release_assertions"
require_relative "../lib/app_store_review_draft"

class AppStoreReviewDraftTest < ReleaseAssertions
  def setup
    @draft = {
      "id" => "draft", "type" => "reviewSubmissions",
      "attributes" => { "state" => "READY_FOR_REVIEW", "platform" => "IOS", "submittedDate" => nil },
      "relationships" => {
        "app" => { "data" => { "type" => "apps", "id" => "app" } },
        "appStoreVersionForReview" => { "data" => nil }
      }
    }
    @submissions = [@draft]
    @items = { "data" => [] }
    @calls = []
    @messages = []
  end

  def api
    lambda do |method, path, *_|
      @calls << [method, path]
      raise "Review draft checks must be read-only" unless method == :get
      case path
      when "apps/app/reviewSubmissions?filter[platform]=IOS&limit=200"
        { "data" => @submissions }
      when "reviewSubmissions/draft?include=appStoreVersionForReview"
        { "data" => @draft }
      when "reviewSubmissions/draft/items?limit=200"
        @items
      else
        raise "Unexpected offline Apple endpoint #{path}"
      end
    end
  end

  def validate
    AppStoreReviewDraft.validate(app_id: "app", platform: "IOS", version_id: "version", api: api, log: ->(message) { @messages << message })
  end

  def test_empty_unassigned_draft_is_preserved_and_reusable
    assert_equal "draft", validate
    assert @calls.include?([:get, "reviewSubmissions/draft/items?limit=200"])
    assert @calls.all? { |method,| method == :get }
  end

  def test_empty_draft_linked_to_exact_target_is_reusable
    @draft["relationships"]["appStoreVersionForReview"]["data"] = { "type" => "appStoreVersions", "id" => "version" }
    assert_equal "draft", validate
  end

  def test_no_ready_draft_leaves_deliver_to_create_one
    @submissions.clear
    assert_equal nil, validate
    assert_equal 1, @calls.length
  end

  def test_nonempty_draft_is_refused_even_for_the_exact_target
    @items["data"] = [{ "id" => "item", "relationships" => { "appStoreVersion" => { "data" => { "id" => "version" } } } }]
    assert_raises(RuntimeError) { validate }
  end

  def test_ambiguous_ready_drafts_are_refused
    @submissions << @draft.merge("id" => "other")
    assert_raises(RuntimeError) { validate }
  end

  def test_other_platform_or_submitted_draft_is_refused
    [
      -> { @draft["attributes"]["platform"] = "MAC_OS" },
      -> { @draft["attributes"]["submittedDate"] = "2026-10-31T01:00:00Z" }
    ].each do |change|
      setup
      change.call
      assert_raises(RuntimeError) { validate }
    end
  end

  def test_sparse_app_relationship_is_not_required_for_app_scoped_draft
    @draft["relationships"].delete("app")
    assert_equal "draft", validate
    assert_equal [:get, "apps/app/reviewSubmissions?filter[platform]=IOS&limit=200"], @calls.first
  end

  def test_empty_draft_with_informational_prior_version_link_is_reusable
    @draft["relationships"]["appStoreVersionForReview"]["data"] = { "type" => "appStoreVersions", "id" => "prior-version", "meta" => { "informational" => true } }
    assert_equal "draft", validate
    assert @calls.include?([:get, "reviewSubmissions/draft/items?limit=200"])
    assert @messages.last.include?('informationalVersionId="prior-version"')
    assert @messages.last.include?("targetVersion=version")
    assert @messages.last.include?("items=0")
  end

  def test_in_progress_unresolved_or_cancelling_submissions_are_refused
    %w[WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES CANCELING].each do |state|
      setup
      @submissions << @draft.merge("id" => "blocked", "attributes" => { "state" => state })
      assert_raises(RuntimeError) { validate }
      assert_equal 1, @calls.length
    end
  end

  def test_unverified_items_pagination_is_refused
    @items["links"] = { "next" => "unverified-page" }
    assert_raises(RuntimeError) { validate }
  end
end

AppStoreReviewDraftTest.run!
