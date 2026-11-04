require_relative "release_assertions"
require_relative "../lib/prepared_release"

class PreparedReleaseTest < ReleaseAssertions
  def setup
    @version = { "id" => "draft", "attributes" => { "versionString" => "1.0.8", "platform" => "IOS", "appStoreState" => "PREPARE_FOR_SUBMISSION", "releaseType" => "AFTER_APPROVAL" } }
    @build = { "id" => "build-11", "attributes" => { "version" => "11", "processingState" => "VALID", "expired" => false }, "relationships" => { "preReleaseVersion" => { "data" => { "id" => "train" } } } }
    @train = { "type" => "preReleaseVersions", "id" => "train", "attributes" => { "version" => "1.0.8", "platform" => "IOS" } }
    @calls = []
    @linked = nil
  end

  def api
    lambda do |method, path, body = nil|
      @calls << [method, path, body]
      case [method, path]
      when [:get, "appStoreVersions/draft"]
        { "data" => @version }
      when [:patch, "appStoreVersions/draft"]
        @version["attributes"]["releaseType"] = body.fetch(:data).fetch(:attributes).fetch(:releaseType)
        { "data" => @version }
      when [:patch, "appStoreVersions/draft/relationships/build"]
        @linked = { "type" => "builds", "id" => body.fetch(:data).fetch(:id) }
        {}
      when [:get, "appStoreVersions/draft/relationships/build"]
        { "data" => @linked }
      else
        raise "unexpected endpoint" unless method == :get && path.start_with?("builds?")
        parameters = URI.decode_www_form(URI(path).query).to_h
        raise "wrong app or build query" unless parameters["filter[app]"] == "app" && parameters["filter[version]"] == "11"
        { "data" => [@build], "included" => [@train] }
      end
    end
  end

  def attach(build_number: "11")
    PreparedRelease.attach(app_id: "app", version_id: "draft", marketing_version: "1.0.8", build_number: build_number, api: api)
  end

  def assert_no_writes
    refute @calls.any? { |method,| method != :get }
  end

  def test_only_attaches_the_explicit_valid_build_and_keeps_manual_draft
    result = attach
    assert_equal "build-11", result.fetch(:build_id)
    assert_equal "MANUAL", result.fetch(:release_type)
    assert_equal "PREPARE_FOR_SUBMISSION", result.fetch(:state)
    mutations = @calls.select { |method,| method != :get }
    assert_equal ["appStoreVersions/draft", "appStoreVersions/draft/relationships/build"], mutations.map { |_, path| path }
    assert mutations.all? { |method,| method == :patch }
  end

  def test_rejects_absent_or_non_numeric_build_number
    ["", "latest", "11; echo bad", "0"].each do |number|
      assert_raises(RuntimeError) { attach(build_number: number) }
      assert_empty @calls
    end
  end

  def test_rejects_versions_that_have_entered_review_or_release
    %w[WAITING_FOR_REVIEW IN_REVIEW PENDING_DEVELOPER_RELEASE READY_FOR_SALE].each do |state|
      @calls.clear
      @version["attributes"]["appStoreState"] = state
      assert_raises(RuntimeError) { attach }
      assert_no_writes
    end
  end

  def test_rejects_a_different_marketing_version
    @version["attributes"]["versionString"] = "1.0.7"
    assert_raises(RuntimeError) { attach }
    assert_no_writes
  end

  def test_rejects_a_build_from_another_train
    @train["attributes"]["version"] = "1.0.7"
    assert_raises(RuntimeError) { attach }
    assert_no_writes
  end

  def test_rejects_expired_or_processing_builds_before_writes
    @build["attributes"]["expired"] = true
    assert_raises(RuntimeError) { attach }
    assert_no_writes
    @build["attributes"]["expired"] = false
    @build["attributes"]["processingState"] = "PROCESSING"
    assert_raises(RuntimeError) { attach }
    assert_no_writes
  end
end

PreparedReleaseTest.run!
