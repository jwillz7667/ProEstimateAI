require "json"
require "fileutils"
require "tmpdir"

# Stages only the campaign selected for this release. Deliver detects the
# App Store display bucket from each PNG's dimensions, not its directory.
module ListingScreenshots
  LOCALES = %w[en-US en-GB en-AU es-MX es-ES].freeze
  FAMILIES = {
    "iphone-dynamic-island-medium" => [1206, 2622],
    "iphone-dynamic-island-large" => [1320, 2868],
    "iphone-face-id-large" => [1284, 2778],
    "ipad-13" => [2064, 2752],
    "ipad-11" => [1668, 2420]
  }.freeze
  CAMPAIGN = "artifacts/app-store-listing/2026-10-30".freeze
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze

  def self.prepare(root:)
    source = File.realpath(File.join(root, CAMPAIGN))
    manifest = JSON.parse(File.read(File.join(source, "manifest.json")))
    files = FAMILIES.flat_map do |id, dimensions|
      families = manifest.fetch("families").select { |family| family.fetch("id") == id }
      raise "Expected exactly one screenshot family #{id}" unless families.length == 1
      family = families.first
      raise "Incorrect manifest dimensions for #{id}" unless [family.fetch("width"), family.fetch("height")] == dimensions
      paths = family.fetch("files")
      raise "Expected three ordered screenshots for #{id}" unless paths.length == 3 && paths.map { |path| File.basename(path)[0, 2] } == %w[01 02 03]

      paths.map do |relative_path|
        path = File.realpath(File.join(source, relative_path))
        raise "Screenshot escapes the selected campaign" unless path.start_with?(source + File::SEPARATOR)
        validate_png!(path, dimensions)
        [path, "#{id}-#{File.basename(path)}"]
      end
    end

    # The 2048 × 2732 export and 2064 × 2752 export share Apple's iPad
    # 12.9/13-inch bucket. Upload only the latter, keeping three panels per
    # bucket and preserving their continuous background in 01 → 02 → 03 order.
    build = File.join(root, "build")
    FileUtils.mkdir_p(build)
    destination = Dir.mktmpdir("listing-screenshots-", build)
    LOCALES.each do |locale|
      localized = File.join(destination, locale)
      FileUtils.mkdir_p(localized)
      files.each { |path, name| FileUtils.copy_file(path, File.join(localized, name)) }
    end
    destination
  end

  def self.validate_png!(path, dimensions)
    header = File.binread(path, 29)
    unless header.bytesize == 29 && header.start_with?(PNG_SIGNATURE) &&
           header.byteslice(8, 8) == [13].pack("N") + "IHDR"
      raise "Invalid PNG header: #{File.basename(path)}"
    end
    actual = header.byteslice(16, 8).unpack("NN")
    unless actual == dimensions && header.getbyte(24) == 8 && header.getbyte(25) == 2
      raise "Expected #{dimensions.join(' × ')} 8-bit RGB PNG without alpha: #{File.basename(path)}"
    end
  end
end
