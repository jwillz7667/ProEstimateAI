# Run with: bundle exec ruby fastlane/tests/beta_safety_test.rb
# No Apple credentials, macOS keychain, Xcode or network calls are used.
require "base64"
require "tmpdir"
require "plist"
require "fastlane"
require "sigh/options"

FASTFILE = File.expand_path("../Fastfile", __dir__)

module SafetyTestUI
  def self.user_error!(message)
    raise message
  end

  def self.message(*) = nil
  def self.important(*) = nil
  def self.success(*) = nil
end

class BetaHarness
  UI = SafetyTestUI
  module SharedValues
    SIGH_PROFILE_PATH = :profile_path
  end

  attr_reader :calls, :certificate_path, :sigh_options
  attr_accessor :fail_at, :profile_xml

  def initialize
    @calls = []
    @lanes = {}
    @profile_xml = { "Name" => "Existing AppStore", "UUID" => "test-profile" }.to_plist
    instance_eval(File.read(FASTFILE), FASTFILE)
  end

  def default_platform(*) = nil
  def desc(*) = nil
  def error(*) = nil
  def platform(*) = yield
  def lane(name, &block) = @lanes[name] = block
  def run = @lanes.fetch(:beta).call
  def lane_context = { SharedValues::SIGH_PROFILE_PATH => "/fake/existing.mobileprovision" }

  def record(name, options = {})
    @calls << [name, options]
    raise "mock #{name} failure" if @fail_at == name
  end

  def app_store_connect_api_key(**options)
    record(:api_key, options)
    { key_id: "FAKE", issuer_id: "FAKE", key: "FAKE" }
  end

  def latest_testflight_build_number(**options)
    record(:latest_build, options)
    10
  end

  def increment_build_number(**options) = record(:increment, options)
  def create_keychain(**options) = record(:create_keychain, options)
  def delete_keychain(**options) = record(:delete_keychain, options)
  def build_ios_app(**options) = record(:build, options)
  def upload_to_testflight(**options) = record(:upload, options)

  def import_certificate(**options)
    @certificate_path = options.fetch(:certificate_path)
    raise "bad certificate fixture" unless File.binread(@certificate_path) == "existing-certificate-fixture"
    raise "certificate file is not private" unless (File.stat(@certificate_path).mode & 0o777) == 0o600
    record(:import_certificate, options)
  end

  def sigh(**options)
    @sigh_options = options
    # Exercise the real pinned Fastlane option validator. In particular,
    # readonly:true + force:false is rejected by Fastlane 2.233.1.
    FastlaneCore::Configuration.create(Sigh::Options.available_options, options)
    record(:sigh, options)
  end

  def `(command)
    raise "unexpected shell command: #{command}" unless command == 'security cms -D -i "/fake/existing.mobileprovision"'
    record(:decode_profile)
    @profile_xml
  end

  def method_missing(name, *)
    raise "Unexpected action #{name}: tests must never contact Apple, create credentials or submit to App Review"
  end
end

def assert(condition, message)
  raise message unless condition
end

def expect_failure(fragment)
  begin
    yield
  rescue => error
    assert(error.message.include?(fragment), "Expected #{fragment.inspect}, got #{error.message.inspect}")
    return
  end
  raise "Expected failure containing #{fragment.inspect}"
end

def with_fixture_env
  original = ENV.to_h
  # Remove developer overrides, including the workflow's .p8 path. The
  # tests validate the lane's explicit configuration with fake values only.
  ENV.keys.grep(/\A(?:SIGH_|APP_STORE_CONNECT_|DIST_CERT_)/).each { |key| ENV.delete(key) }
  ENV.update(
    "APP_STORE_CONNECT_API_KEY_ID" => "FAKE",
    "APP_STORE_CONNECT_API_KEY_ISSUER_ID" => "FAKE",
    "APP_STORE_CONNECT_API_KEY_CONTENT" => "FAKE",
    "DIST_CERT_P12_BASE64" => Base64.strict_encode64("existing-certificate-fixture"),
    "DIST_CERT_P12_PASSWORD" => "fixture-password"
  )
  yield
ensure
  ENV.replace(original)
end

tests = {}
tests["App Store access failure stops before signing or upload"] = lambda do
  harness = BetaHarness.new
  harness.fail_at = :latest_build
  expect_failure("mock latest_build failure") { harness.run }
  assert(!harness.calls.assoc(:increment), "must not guess a build number after App Store access fails")
  assert(!harness.calls.assoc(:create_keychain), "must not start signing after App Store access fails")
  assert(!harness.calls.assoc(:upload), "must not upload after App Store access fails")
end
tests["existing certificate and read-only profile upload internally"] = lambda do
  harness = BetaHarness.new
  harness.run
  sigh = harness.sigh_options
  assert(sigh[:readonly] == true, "provisioning must be read-only")
  assert(!sigh.key?(:force), "force must be omitted, not false")
  assert(sigh[:skip_certificate_verification] == false, "certificate matching must stay enabled")
  assert(harness.calls.assoc(:increment).last[:build_number] == 11, "build number should increment")
  build = harness.calls.assoc(:build).last
  assert(build[:export_options][:signingStyle] == "manual", "manual export signing is required")
  assert(build[:export_options][:provisioningProfiles]["Res.ProEstimate-AI"] == "Existing AppStore", "use the downloaded profile")
  assert(!build[:xcargs].include?("allowProvisioning"), "Xcode must not mutate provisioning")
  upload = harness.calls.assoc(:upload).last
  assert(upload[:distribute_external] == false, "external distribution must remain disabled")
  assert(!File.exist?(harness.certificate_path), "temporary certificate file was not cleaned up")
  assert(harness.calls.last.first == :delete_keychain, "keychain cleanup must run after upload")
end

%w[DIST_CERT_P12_BASE64 DIST_CERT_P12_PASSWORD].each do |name|
  [nil, "", "   "].each do |value|
    tests["reject #{name} = #{value.inspect} before any action"] = lambda do
      ENV[name] = value
      harness = BetaHarness.new
      expect_failure(name) { harness.run }
      assert(harness.calls.empty?, "missing signing credentials must fail before any action")
    end
  end
end

["", " ", "true", "false", "1", "yes", "invalid"].each do |value|
  tests["reject SIGH_FORCE override #{value}"] = lambda do
    ENV["SIGH_FORCE"] = value
    harness = BetaHarness.new
    expect_failure("SIGH_FORCE") { harness.run }
    assert(harness.calls.empty?, "force override must fail before any action")
  end
end

tests["invalid base64 stops before certificate import"] = lambda do
  ENV["DIST_CERT_P12_BASE64"] = "%%%invalid%%%"
  harness = BetaHarness.new
  expect_failure("invalid base64") { harness.run }
  assert(!harness.calls.assoc(:import_certificate), "invalid data must not be imported")
  assert(harness.calls.last.first == :delete_keychain, "keychain cleanup must run on invalid certificate data")
end

%i[import_certificate sigh build upload].each do |action|
  tests["#{action} failure cleans up without fallback"] = lambda do
    harness = BetaHarness.new
    harness.fail_at = action
    expect_failure("mock #{action} failure") { harness.run }
    assert(harness.calls.last.first == :delete_keychain, "keychain cleanup must run on #{action} failure")
    assert(!File.exist?(harness.certificate_path), "temporary certificate file leaked")
    assert(!harness.calls.assoc(:upload), "must not upload after #{action} failure") unless action == :upload
  end
end

tests["missing provisioning profile name fails before archive"] = lambda do
  harness = BetaHarness.new
  harness.profile_xml = { "UUID" => "missing-name" }.to_plist
  expect_failure("no Name field") { harness.run }
  assert(!harness.calls.assoc(:build), "must not archive without a profile name")
  assert(harness.calls.last.first == :delete_keychain, "keychain cleanup must run on invalid profile")
end

tests.each do |name, test|
  with_fixture_env { test.call }
  puts "PASS: #{name}"
end
puts "#{tests.length} release safety tests passed (mocked actions, no Apple access)."
