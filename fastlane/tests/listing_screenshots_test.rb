require_relative "release_assertions"
require_relative "../lib/listing_screenshots"

class ListingScreenshotsTest < ReleaseAssertions
  def setup
    @root = Dir.mktmpdir("listing-fixture-")
    @campaign = File.join(@root, ListingScreenshots::CAMPAIGN)
    FileUtils.mkdir_p(@campaign)
    @families = ListingScreenshots::FAMILIES.map do |id, dimensions|
      files = (1..3).map do |index|
        relative = "#{id}/#{format('%02d', index)}-panel.png"
        path = File.join(@campaign, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, png_header(dimensions))
        relative
      end
      { "id" => id, "width" => dimensions[0], "height" => dimensions[1], "files" => files }
    end
    save_manifest
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def png_header(dimensions, color_type: 2)
    ListingScreenshots::PNG_SIGNATURE + [13].pack("N") + "IHDR" + dimensions.pack("NN") + [8, color_type, 0, 0, 0].pack("C*")
  end

  def save_manifest
    File.write(File.join(@campaign, "manifest.json"), JSON.generate("families" => @families))
  end

  def test_stages_exactly_three_ordered_panels_per_display_bucket_in_each_locale
    # The optional 12.9-inch export must never join the same bucket as 13-inch.
    @families << { "id" => "ipad-12-9", "width" => 2048, "height" => 2732, "files" => ["not-selected.png"] }
    save_manifest
    path = ListingScreenshots.prepare(root: @root)
    assert_equal ListingScreenshots::LOCALES.sort, Dir.children(path).sort
    ListingScreenshots::LOCALES.each do |locale|
      files = Dir.children(File.join(path, locale)).sort
      assert_equal 15, files.length
      refute files.any? { |file| file.include?("ipad-12-9") }
      ListingScreenshots::FAMILIES.each_key do |family|
        selected = files.select { |file| file.start_with?(family + "-") }
        assert_equal %w[01 02 03], selected.map { |file| file.delete_prefix(family + "-")[0, 2] }
      end
    end
  end

  def test_rejects_alpha_before_staging_any_files
    family = @families.first
    File.binwrite(File.join(@campaign, family.fetch("files").first), png_header([family["width"], family["height"]], color_type: 6))
    assert_raises(RuntimeError) { ListingScreenshots.prepare(root: @root) }
    refute File.exist?(File.join(@root, "build"))
  end

  def test_rejects_missing_or_duplicate_panels
    @families.first["files"][1] = @families.first["files"][0]
    save_manifest
    assert_raises(RuntimeError) { ListingScreenshots.prepare(root: @root) }
  end

  def test_rejects_incorrect_actual_dimensions
    path = File.join(@campaign, @families.first.fetch("files").first)
    File.binwrite(path, png_header([1, 1]))
    assert_raises(RuntimeError) { ListingScreenshots.prepare(root: @root) }
  end

  def test_rejects_symlink_outside_campaign
    external = File.join(@root, "external.png")
    path = File.join(@campaign, @families.first.fetch("files").first)
    File.write(external, File.binread(path))
    File.unlink(path)
    File.symlink(external, path)
    assert_raises(RuntimeError) { ListingScreenshots.prepare(root: @root) }
  end
end

ListingScreenshotsTest.run!
