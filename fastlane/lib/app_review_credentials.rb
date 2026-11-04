# App Review passwords belong in the release environment, never metadata files.
module AppReviewCredentials
  ENV_KEY = "APP_REVIEW_DEMO_PASSWORD".freeze

  def self.load(root:, env: ENV)
    password = env[ENV_KEY].to_s.strip
    raise "#{ENV_KEY} must be set for App Review metadata updates" if password.empty?

    username = File.read(File.join(root, "fastlane/metadata/review_information/demo_user.txt")).strip
    raise "App Review demo username must not be blank" if username.empty?

    # Deliver masks this exact nested key in its summary. Other review fields
    # (contact details and notes) continue to load from public metadata files.
    { demo_user: username, demo_password: password }
  end
end
