# Run with: bundle exec ruby fastlane/tests/app_review_credentials_test.rb
# Every release action and HTTP transport is replaced with an offline fixture.
require "fastlane"
require "deliver/runner"
require "json"
require "stringio"
require "tmpdir"
require_relative "release_assertions"
require_relative "../lib/app_review_credentials"

module ReviewTestUI
  class << self
    attr_accessor :messages
    def user_error!(message) = raise(message)
    def message(message) = messages << message
    def important(message) = messages << message
    def success(message) = messages << message
  end
end

class ReviewLaneHarness
  UI = ReviewTestUI
  attr_reader :calls, :delivery

  def initialize(calls)
    @calls = calls
    @lanes = {}
    path = File.expand_path("../Fastfile", __dir__)
    instance_eval(File.read(path), path)
    define_singleton_method(:setup_spaceship_token) { @calls << :setup_token }
    define_singleton_method(:ensure_editable_app_store_version) { |_| @calls << :ensure_version }
    define_singleton_method(:make_api_key) do
      @calls << :api_key
      { key_id: "OFFLINE", issuer_id: "OFFLINE", key: "OFFLINE" }
    end
  end

  def default_platform(*) = nil
  def desc(*) = nil
  def error(*) = nil
  def platform(*) = yield
  def lane(name, &block) = @lanes[name] = block
  def run(name) = @lanes.fetch(name).call

  def deliver(**options)
    @calls << :deliver
    @delivery = options
  end

  def method_missing(name, *)
    raise "Unexpected action #{name}: tests must never access Apple or signing credentials"
  end
end

class ReviewFixtureHTTP
  attr_accessor :use_ssl, :open_timeout, :read_timeout

  def initialize(&fixture)
    @fixture = fixture
  end

  def request(request)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.body = JSON.generate(@fixture.call(request))
    response.instance_variable_set(:@read, true)
    response
  end
end

class AppReviewCredentialsTest < ReleaseAssertions
  ROOT = File.expand_path("../..", __dir__)
  FIXTURE_PASSWORD = "offline-review-password-fixture".freeze

  def setup
    # The test process is disposable. Replace rather than inspect any real
    # credentials inherited from the developer's shell.
    ENV["APP_REVIEW_DEMO_PASSWORD"] = FIXTURE_PASSWORD
    ENV["APP_STORE_CONNECT_API_KEY_CONTENT"] = "OFFLINE"
    ENV["APP_STORE_CONNECT_API_KEY_ID"] = "OFFLINE"
    ENV["APP_STORE_CONNECT_API_KEY_ISSUER_ID"] = "OFFLINE"
    ENV["FL_SKIP_TABLE_TRANSFORM"] = "1"
    ENV.delete("FASTLANE_SKIP_ALL_LANE_SUMMARIES")
    @calls = []
    @stubs = []
    ReviewTestUI.messages = []
    @harness = ReviewLaneHarness.new(@calls)
    @version = @harness.project_marketing_version
    @root = Dir.mktmpdir("review-credentials-fixture-")
    folder = File.join(@root, "fastlane/metadata/review_information")
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "demo_user.txt"), "offline-review@example.com\n")
    File.write(File.join(folder, "demo_password.txt"), "obsolete fixture password")

    calls = @calls
    stub(ListingScreenshots, :prepare) do |root:|
      calls << [:prepare_screenshots, root]
      "/offline/selected-listing-screenshots"
    end
    stub(Spaceship::ConnectAPI::App, :find) do |_|
      calls << :find_app
      Struct.new(:id).new("offline-app")
    end
    token = Struct.new(:text).new("offline-token")
    stub(Spaceship::ConnectAPI::Token, :create) do |**_|
      calls << :create_token
      token
    end
    stub(Spaceship::ConnectAPI, :token) { token }
    stub(Spaceship::ConnectAPI, :token=) { |value| token = value }
    fixture = ReviewFixtureHTTP.new { |request| http_fixture(request) }
    stub(Net::HTTP, :new) { |*| fixture }
    stub(Net::HTTP, :start) { |*, **_, &block| block.call(fixture) }
  end

  def teardown
    @stubs.reverse_each { |object, name, original| object.define_singleton_method(name, original) }
    FileUtils.remove_entry(@root) if @root
  end

  def stub(object, name, &replacement)
    @stubs << [object, name, object.method(name)]
    object.define_singleton_method(name, &replacement)
  end

  def http_fixture(request)
    @calls << [:http, request.method, request.path]
    raise "Unexpected write in offline fixture" unless request.method == "GET"

    case request.path
    when %r{\A/v1/preReleaseVersions\?}
      { data: [{ id: "offline-train" }] }
    when %r{\A/v1/builds\?filter\[preReleaseVersion\]}
      { data: [{ id: "offline-build", attributes: { version: "11", processingState: "VALID" } }] }
    when %r{\A/v1/reviewSubmissions\?}, %r{\A/v1/builds\?filter\[app\]},
         %r{\A/v1/apps/offline-app/(appInfos|subscriptionGroups|buildUploads)\?},
         %r{\A/v1/appStoreVersions/offline-draft/appStoreVersionLocalizations\?}
      { data: [] }
    when %r{\A/v1/apps/offline-app/appStoreVersions\?}
      { data: [{ id: "offline-draft", attributes: { versionString: @version, appStoreState: "PREPARE_FOR_SUBMISSION" } }] }
    when "/v1/appStoreVersions/offline-draft/relationships/build"
      { data: { id: "offline-build", type: "builds" } }
    when %r{\A/v1/appStoreVersions/offline-draft/appStoreReviewDetail\?}
      fields = URI.decode_www_form(URI(request.path).query).to_h.fetch("fields[appStoreReviewDetails]")
      assert_equal "notes,demoAccountRequired", fields
      { data: { attributes: { notes: "offline review notes", demoAccountRequired: true } } }
    else
      raise "Unexpected offline endpoint: #{request.path}"
    end
  end

  def test_missing_or_blank_password_stops_all_writing_lanes_before_any_action
    [nil, "", " \t\n"].each do |value|
      ENV["APP_REVIEW_DEMO_PASSWORD"] = value
      %i[metadata metadata_copy submit].each do |lane|
        @calls.clear
        begin
          @harness.run(lane)
          raise "Expected missing-secret failure"
        rescue RuntimeError => error
          assert error.message.include?("APP_REVIEW_DEMO_PASSWORD must be set")
        end
        assert_empty @calls
      end
    end
  end

  def test_helper_uses_environment_secret_and_public_username_without_file_fallback
    information = AppReviewCredentials.load(root: @root, env: { "APP_REVIEW_DEMO_PASSWORD" => FIXTURE_PASSWORD })
    assert_equal "offline-review@example.com", information.fetch(:demo_user)
    assert information.fetch(:demo_password) == FIXTURE_PASSWORD
    assert_raises(RuntimeError) { AppReviewCredentials.load(root: @root, env: {}) }
  end

  def test_metadata_lanes_inject_credentials_without_submitting_a_build
    %i[metadata metadata_copy].each do |lane|
      @harness.run(lane)
      options = @harness.delivery
      assert options.fetch(:app_review_information).fetch(:demo_password) == FIXTURE_PASSWORD
      assert_equal File.read(File.join(ROOT, "fastlane/metadata/review_information/demo_user.txt")).strip,
                   options.fetch(:app_review_information).fetch(:demo_user)
      assert_equal false, options.fetch(:submit_for_review)
      assert_equal true, options.fetch(:skip_binary_upload)
    end
  end

  def test_submit_uses_selected_campaign_and_preserves_completed_screenshots
    @harness.run(:submit)
    options = @harness.delivery
    assert options.fetch(:app_review_information).fetch(:demo_password) == FIXTURE_PASSWORD
    assert_equal "/offline/selected-listing-screenshots", options.fetch(:screenshots_path)
    assert_equal false, options.fetch(:overwrite_screenshots)
    assert (1..300).cover?(options.fetch(:screenshot_processing_timeout))
    assert_equal true, options.fetch(:submit_for_review)
    assert_equal false, options.fetch(:automatic_release)
    assert_equal true, options.fetch(:skip_binary_upload)
    assert_equal [:prepare_screenshots, ROOT], @calls.first
  end

  def test_screenshot_lanes_need_no_secret_and_pass_no_review_credentials
    ENV.delete("APP_REVIEW_DEMO_PASSWORD")
    %i[metadata_screenshots metadata_recover_screenshots].each do |lane|
      @harness.run(lane)
      options = @harness.delivery
      assert_equal true, options.fetch(:skip_metadata)
      refute options.key?(:app_review_information)
      assert_equal false, options.fetch(:submit_for_review)
      # Exercise the pinned loader: skip_metadata must prevent review-file reads.
      Deliver::UploadMetadata.new(options.merge(metadata_path: "/must-not-be-read")).load_from_filesystem
    end
  end

  def test_status_needs_no_secret_and_limits_review_fields_at_the_api_boundary
    ENV.delete("APP_REVIEW_DEMO_PASSWORD")
    @harness.run(:asc_status)
    summary = JSON.parse(ReviewTestUI.messages.last)
    assert_equal %w[demo_account_required notes_match_source notes_sha256], summary.fetch("listing").fetch("review").keys.sort
    refute ReviewTestUI.messages.join.include?(FIXTURE_PASSWORD)
    refute ReviewTestUI.messages.join.include?("demoAccountPassword")
    refute ReviewTestUI.messages.join.include?("demoAccountName")
    refute @calls.include?(:deliver)
  end

  def test_pinned_deliver_summary_masks_nested_demo_password
    assert_equal "2.233.1", Fastlane::VERSION
    runner = Class.new(Deliver::Runner) { def login = nil }
    original_detection = Deliver::DetectValues.instance_method(:run!)
    Deliver::DetectValues.define_method(:run!) { |*| nil }
    original_stdout = $stdout
    output = StringIO.new
    $stdout = output
    runner.new(app_review_information: { demo_user: "offline-review@example.com", demo_password: FIXTURE_PASSWORD })
    refute output.string.include?(FIXTURE_PASSWORD)
    assert output.string.include?("********")
  ensure
    $stdout = original_stdout if original_stdout
    Deliver::DetectValues.define_method(:run!, original_detection) if original_detection
  end

  def test_review_password_file_is_absent_from_release_metadata
    refute File.exist?(File.join(ROOT, "fastlane/metadata/review_information/demo_password.txt"))
  end
end

AppReviewCredentialsTest.run!
