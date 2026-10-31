require "json"
require_relative "release_assertions"
require_relative "../lib/app_store_age_rating"

class AppStoreAgeRatingTest < ReleaseAssertions
  def setup
    @infos = [{ "id" => "editable-info", "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION" } }]
    @attributes = {
      "socialMedia" => nil, "socialMediaAgeRestricted" => nil,
      "userGeneratedContent" => false, "unrestrictedWebAccess" => false,
      "messagingAndChat" => false, "profanityOrCrudeHumor" => "NONE",
      "ageRatingOverrideV2" => nil
    }
    @calls = []
    @messages = []
    @reads = 0
  end

  def api
    lambda do |method, path, body = nil|
      @calls << [method, path, body]
      case [method, path]
      when [:get, "apps/app/appInfos?limit=200"]
        { "data" => @infos }
      when [:get, "appInfos/editable-info/ageRatingDeclaration"]
        @reads += 1
        attributes = Marshal.load(Marshal.dump(@attributes))
        attributes["userGeneratedContent"] = true if @readback_drift && @reads > 1
        attributes["socialMedia"] = nil if @readback_unconfirmed && @reads > 1
        { "data" => { "id" => "rating", "type" => "ageRatingDeclarations", "attributes" => attributes } }
      when [:patch, "ageRatingDeclarations/rating"]
        @attributes["socialMedia"] = false
        { "data" => { "id" => "rating" } }
      else
        raise "Unexpected offline request: #{method} #{path}"
      end
    end
  end

  def run_preflight
    AppStoreAgeRating.ensure_social_media_declaration(app_id: "app", api: api, log: ->(message) { @messages << message })
  end

  def mutations = @calls.reject { |method,| method == :get }

  def test_null_answer_patches_only_social_media_and_independently_reads_back
    original = Marshal.load(Marshal.dump(@attributes))
    result = run_preflight
    assert_equal true, result[:updated]
    assert_equal [[:patch, "ageRatingDeclarations/rating", {
      data: { type: "ageRatingDeclarations", id: "rating", attributes: { socialMedia: false } }
    }]], mutations
    assert_equal original.merge("socialMedia" => false), @attributes
    assert_equal 2, @reads
    assert @messages.last.include?("otherAnswers=preserved")
  end

  def test_missing_answer_is_completed_without_filling_other_missing_fields
    @attributes.delete("socialMedia")
    @attributes.delete("ageAssurance")
    run_preflight
    assert_equal false, @attributes["socialMedia"]
    refute @attributes.key?("ageAssurance")
    assert_equal 1, mutations.length
  end

  def test_already_false_is_idempotent_and_verified
    @attributes["socialMedia"] = false
    assert_equal false, run_preflight[:updated]
    assert_empty mutations
    assert_equal 2, @reads
  end

  def test_true_answer_is_never_silently_downgraded
    @attributes["socialMedia"] = true
    assert_raises(RuntimeError) { run_preflight }
    assert_empty mutations
    assert_equal true, @attributes["socialMedia"]
  end

  def test_unknown_answer_type_stops_without_mutation
    @attributes["socialMedia"] = "false"
    assert_raises(RuntimeError) { run_preflight }
    assert_empty mutations
  end

  def test_no_editable_app_info_stops_without_mutation
    @infos.first["attributes"]["appStoreState"] = "READY_FOR_DISTRIBUTION"
    assert_raises(RuntimeError) { run_preflight }
    assert_empty mutations
  end

  def test_ambiguous_editable_app_infos_stop_without_mutation
    @infos << { "id" => "other-info", "attributes" => { "appStoreState" => "REJECTED" } }
    assert_raises(RuntimeError) { run_preflight }
    assert_empty mutations
  end

  def test_live_app_info_does_not_obscure_the_single_editable_info
    @infos.unshift({ "id" => "live-info", "attributes" => { "appStoreState" => "READY_FOR_DISTRIBUTION" } })
    assert_equal "editable-info", run_preflight[:app_info_id]
  end

  def test_other_questionnaire_change_in_readback_stops_submission
    @readback_drift = true
    begin
      run_preflight
      raise "Expected readback mismatch"
    rescue RuntimeError => error
      assert error.message.include?("userGeneratedContent: before=false expected=false after=true")
    end
    assert_equal 2, @reads
  end

  def test_unsaved_social_media_answer_in_readback_stops_submission
    @readback_unconfirmed = true
    assert_raises(RuntimeError) { run_preflight }
  end

  def test_unrelated_true_capabilities_remain_exactly_as_declared
    @attributes["userGeneratedContent"] = true
    @attributes["socialMediaAgeRestricted"] = true
    run_preflight
    assert_equal true, @attributes["userGeneratedContent"]
    assert_equal true, @attributes["socialMediaAgeRestricted"]
  end
end

AppStoreAgeRatingTest.run!
