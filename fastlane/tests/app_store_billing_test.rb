require_relative "release_assertions"
require_relative "../lib/app_store_billing"

class AppStoreBillingTest < ReleaseAssertions
  def setup
    @report = { app_id: "app", products: AppStoreBilling::PRODUCTS.each_with_index.map do |id, index|
      { id: "product-#{index}", group_id: "group", attributes: { "productId" => id, "state" => "APPROVED" },
        availability: { territories: %w[USA GBR AUS] }, introductory_offers: [],
        prices: [{ id: "price-#{index}", attributes: { "startDate" => nil }, price_point: { "id" => "point-#{index}" } }] }
    end }
    @calls = []
  end

  def api
    lambda do |method, target, body = nil|
      @calls << [method, target, body]
      if method == :delete
        @report[:products].each { |product| product[:introductory_offers].reject! { |item| target == "subscriptionIntroductoryOffers/#{item[:id]}" } }
      elsif method == :post
        data = JSON.parse(JSON.generate(body)).fetch("data")
        territory = data.dig("relationships", "territory", "data", "id")
        raise "Apple requires an explicit territory" if territory.nil?
        product = @report[:products].find { |item| item[:id] == data.dig("relationships", "subscription", "data", "id") }
        if data.dig("attributes", "duration") == "THREE_DAYS"
          raise "Simulated Apple rejection" if @fail_monthly && product == @report[:products].first
          raise "Simulated partial annual failure" if @fail_annual_gbr && product == @report[:products].last && territory == "GBR"
        end
        product[:introductory_offers] << { id: "new-#{@calls.length}", territory: territory, attributes: data.fetch("attributes") }
        if @change_prices_on_creation
          product[:prices].first[:price_point] = { "id" => "changed-point" }
        end
        if @timeout_after_creation
          @timeout_after_creation = false
          raise "POST timed out after acceptance"
        end
        if @timeout_restore && data.dig("attributes", "duration") == "ONE_WEEK"
          raise "Restore timed out after acceptance"
        end
      end
      {}
    end
  end

  def snapshot = Marshal.load(Marshal.dump(@report))
  def plan = AppStoreBilling.trial_plan(report: @report, today: "2026-10-30")
  def apply(operations = plan)
    AppStoreBilling.apply_trial(plan: operations, report: snapshot, api: api, readback: -> { snapshot })
  end

  def offer(duration: "ONE_WEEK", territory: "USA", mode: "FREE_TRIAL", id: "old-offer")
    { id: id, territory: territory, attributes: { "duration" => duration, "offerMode" => mode, "numberOfPeriods" => 1, "startDate" => "2026-04-24", "endDate" => nil } }
  end

  def assert_complete_coverage
    assert plan.all? { |item| !item[:create] && item[:remove_offer_ids].empty? }
    @report[:products].each do |product|
      product[:availability][:territories].each do |territory|
        assert AppStoreBilling.territory_configured?(product, territory, "2026-10-30")
      end
    end
  end

  def test_replaces_only_introductory_metadata_with_explicit_territories
    @report[:products].first[:introductory_offers] << offer
    operations = plan
    assert_equal ["old-offer"], operations.first[:remove_offer_ids]
    apply(operations)
    assert_equal 7, @calls.length
    assert_equal :post, @calls.first[0]
    assert_equal "product-1", @calls.first[2].dig(:data, :relationships, :subscription, :data, :id)
    assert_equal "USA", @calls.first[2].dig(:data, :relationships, :territory, :data, :id)
    deletion_index = @calls.index { |method,| method == :delete }
    assert_equal 3, deletion_index
    assert @calls.all? { |method, target| %i[post delete].include?(method) && target.start_with?("subscriptionIntroductoryOffers") }
    @calls.select { |method,| method == :post }.each do |_, _, body|
      data = body.fetch(:data)
      assert_equal "THREE_DAYS", data[:attributes][:duration]
      assert_equal "FREE_TRIAL", data[:attributes][:offerMode]
      assert_equal 1, data[:attributes][:numberOfPeriods]
      refute data[:relationships].key?(:subscriptionPricePoint)
      assert %w[USA GBR AUS].include?(data.dig(:relationships, :territory, :data, :id))
    end
    assert_complete_coverage
  end

  def test_full_175_country_coverage_on_both_products_and_idempotent_resume
    countries = ["USA"] + (1..174).map { |number| "X#{number.to_s.rjust(3, '0')}" }
    @report[:products].each { |product| product[:availability][:territories] = countries }
    @report[:products].first[:introductory_offers] << offer
    apply
    assert_equal 350, @calls.count { |method,| method == :post }
    assert_equal 175, @calls.index { |method,| method == :delete }
    assert_complete_coverage
    @calls.clear
    apply
    assert_empty @calls
  end

  def test_partial_annual_failure_retains_monthly_and_resumes_missing_countries_only
    @report[:products].first[:introductory_offers] << offer
    @fail_annual_gbr = true
    assert_raises(RuntimeError) { apply }
    annual_usa = @report[:products].last[:introductory_offers].find { |item| item[:territory] == "USA" }[:id]
    assert_equal "old-offer", @report[:products].first[:introductory_offers].first[:id]
    refute @calls.any? { |method,| method == :delete }
    @fail_annual_gbr = false
    @calls.clear
    apply
    assert_complete_coverage
    assert_equal annual_usa, @report[:products].last[:introductory_offers].find { |item| item[:territory] == "USA" }[:id]
    annual_post_countries = @calls.filter_map do |method, _, body|
      next unless method == :post && body.dig(:data, :relationships, :subscription, :data, :id) == "product-1"
      body.dig(:data, :relationships, :territory, :data, :id)
    end
    assert_equal ["GBR"], annual_post_countries
  end

  def test_configured_scoped_or_historical_global_trial_is_idempotent
    @report[:products].each { |product| product[:introductory_offers] << offer(duration: "THREE_DAYS", territory: nil) }
    apply
    assert_empty @calls
    @report[:products].each do |product|
      product[:introductory_offers] = product[:availability][:territories].map { |country| offer(duration: "THREE_DAYS", territory: country, id: country) }
    end
    apply
    assert_empty @calls
  end

  def test_expired_historical_offer_is_preserved
    historical = offer
    historical[:attributes]["endDate"] = "2026-05-01"
    @report[:products].first[:introductory_offers] << historical
    apply
    assert @report[:products].first[:introductory_offers].any? { |item| item[:id] == "old-offer" }
    assert_complete_coverage
  end

  def test_unapproved_unavailable_and_duplicate_availability_fail_before_writes
    @report[:products].first[:attributes]["state"] = "READY_TO_SUBMIT"
    assert_raises(RuntimeError) { plan }
    @report[:products].first[:attributes]["state"] = "APPROVED"
    @report[:products].first[:availability][:territories] = []
    assert_raises(RuntimeError) { plan }
    @report[:products].first[:availability][:territories] = %w[USA USA]
    assert_raises(RuntimeError) { plan }
    assert_empty @calls
  end

  def test_wrong_group_or_product_cannot_receive_trial
    @report[:products].last[:group_id] = "other"
    assert_raises(RuntimeError) { plan }
    @report[:products].last[:group_id] = "group"
    @report[:products].last[:attributes]["productId"] = "other.product"
    assert_raises(RuntimeError) { plan }
  end

  def test_nonfree_promotion_is_rejected_and_duplicate_scoped_trials_retain_one
    @report[:products].first[:introductory_offers] << offer(mode: "PAY_UP_FRONT")
    assert_raises(RuntimeError) { plan }
    @report[:products].first[:introductory_offers] = [offer(duration: "THREE_DAYS", id: "a"), offer(duration: "THREE_DAYS", id: "z")]
    usa = plan.first[:territories].find { |item| item[:territory] == "USA" }
    assert_equal ["z"], usa[:remove_offer_ids]
    refute usa[:create]
    apply
    assert_complete_coverage
    assert @report[:products].first[:introductory_offers].any? { |item| item[:id] == "a" }
  end

  def test_monthly_rejection_restores_seven_day_offer_even_with_other_countries_present
    @report[:products].first[:introductory_offers] = [offer, offer(duration: "THREE_DAYS", territory: "GBR", id: "existing-gbr")]
    @fail_monthly = true
    assert_raises(RuntimeError) { apply }
    monthly = @report[:products].first[:introductory_offers]
    usa = monthly.select { |item| item[:territory] == "USA" }
    assert_equal 1, usa.length
    assert_equal "ONE_WEEK", usa.first[:attributes]["duration"]
    assert monthly.any? { |item| item[:id] == "existing-gbr" }
    refute plan.last[:create]
  end

  def test_ambiguous_creation_is_read_back_without_duplicate_post
    @timeout_after_creation = true
    apply
    assert_complete_coverage
    usa_posts = @calls.count do |method, _, body|
      method == :post && body.dig(:data, :relationships, :subscription, :data, :id) == "product-1" && body.dig(:data, :relationships, :territory, :data, :id) == "USA"
    end
    assert_equal 1, usa_posts
  end

  def test_ambiguous_compensation_is_verified_without_duplicating_original_offer
    @report[:products].first[:introductory_offers] << offer
    @fail_monthly = true
    @timeout_restore = true
    assert_raises(RuntimeError) { apply }
    usa = @report[:products].first[:introductory_offers].select { |item| item[:territory] == "USA" }
    assert_equal 1, usa.length
    assert_equal "ONE_WEEK", usa.first[:attributes]["duration"]
  end

  def test_changed_prices_abort_before_existing_monthly_offer_is_deleted
    @report[:products].first[:introductory_offers] << offer
    @change_prices_on_creation = true
    assert_raises(RuntimeError) { apply }
    refute @calls.any? { |method,| method == :delete }
    assert_equal "old-offer", @report[:products].first[:introductory_offers].first[:id]
  end

  def test_malformed_complete_plan_cannot_partially_mutate
    invalid = plan
    invalid.last[:subscription_id] = "not-the-inspected-product"
    assert_raises(RuntimeError) { apply(invalid) }
    assert_empty @calls
    invalid = plan
    invalid.last[:territories].last[:remove_offer_ids] << "unrelated-offer"
    assert_raises(RuntimeError) { apply(invalid) }
    assert_empty @calls
    assert_raises(RuntimeError) { apply(plan.take(1)) }
    assert_empty @calls
  end

  def test_unexpected_global_or_annual_conflict_fails_without_deleting_existing_offer
    @report[:products].last[:introductory_offers] << offer
    assert_raises(RuntimeError) { apply }
    assert_empty @calls
    @report[:products].last[:introductory_offers] = [offer(territory: nil)]
    assert_raises(RuntimeError) { plan }
    assert_empty @calls
  end

  def test_pagination_cannot_loop_and_requests_cannot_send_credentials_off_apple
    assert_raises(RuntimeError) { AppStoreBilling.pages("first", api: ->(*) { { "data" => [], "links" => { "next" => "first" } } }) }
    assert_raises(RuntimeError) { AppStoreBilling.request(token: "not-a-secret", method: :get, path: "https://example.com/v1/capture") }
  end
end

AppStoreBillingTest.run!
