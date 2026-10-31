# Complete only the newly required social-media answer for this private
# project-management app. Preserve the rest of Apple's existing questionnaire.
module AppStoreAgeRating
  EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze

  def self.ensure_social_media_declaration(app_id:, api:, log: ->(_message) {})
    infos = []
    path = "apps/#{app_id}/appInfos?limit=200"
    seen = {}
    while path
      raise "Repeated or excessive Apple appInfo pagination" if seen[path] || seen.length >= 10
      seen[path] = true
      page = api.call(:get, path)
      infos.concat(page.fetch("data"))
      path = page.dig("links", "next")
    end
    editable = infos.select { |info| EDITABLE_STATES.include?(info.dig("attributes", "appStoreState")) }
    raise "Expected exactly one editable appInfo for age-rating preflight; found #{editable.length}" unless editable.length == 1

    info_id = editable.first.fetch("id")
    declaration_path = "appInfos/#{info_id}/ageRatingDeclaration"
    before = api.call(:get, declaration_path).fetch("data")
    raise "Missing Apple age-rating declaration" unless before.is_a?(Hash) && before["type"] == "ageRatingDeclarations"
    declaration_id = before.fetch("id")
    attributes = before.fetch("attributes")
    value = attributes["socialMedia"]
    if value == true
      raise "Age-rating mismatch: socialMedia is true, but this app has no social feed or discovery. Review the declaration manually; no downgrade was made."
    end
    raise "Unexpected Apple socialMedia value #{value.inspect}" unless value.nil? || value == false

    log.call("Age-rating preflight appInfo=#{info_id} declaration=#{declaration_id} socialMedia=#{value.inspect}")
    if value.nil?
      api.call(:patch, "ageRatingDeclarations/#{declaration_id}", {
        data: { type: "ageRatingDeclarations", id: declaration_id, attributes: { socialMedia: false } }
      })
    end

    # An independent GET, rather than the PATCH response, confirms the saved
    # answer and detects unintended changes to any existing declaration field.
    after = api.call(:get, declaration_path).fetch("data")
    unless after.is_a?(Hash) && after["id"] == declaration_id && after["type"] == "ageRatingDeclarations"
      raise "Apple age-rating declaration changed identity during preflight"
    end
    expected = attributes.merge("socialMedia" => false)
    unless after.fetch("attributes") == expected
      raise "Apple age-rating readback mismatch: socialMedia must be false and all other questionnaire answers must remain unchanged"
    end
    log.call("Age-rating verified appInfo=#{info_id} declaration=#{declaration_id} socialMedia=false otherAnswers=preserved")
    { app_info_id: info_id, declaration_id: declaration_id, social_media: false, updated: value.nil? }
  end
end
