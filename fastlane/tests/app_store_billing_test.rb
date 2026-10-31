require_relative "release_assertions"
require_relative "../lib/app_store_billing"

class AppStoreBillingTest < ReleaseAssertions
  def setup
    @report = { products: AppStoreBilling::PRODUCTS.each_with_index.map do |id, index|
      { id: "product-#{index}", group_id: "group", attributes: { "productId" => id, "state" => "APPROVED" }, availability: { territories: %w[USA GBR AUS] }, introductory_offers: [] }
    end }
    @calls = []
  end

  def api
    lambda do |method, target, body = nil|
      @calls << [method, target, body]
      if method == :delete
        @report[:products].each { |product| product[:introductory_offers].reject! { |item| target.end_with?(item[:id]) } }
      elsif method == :post
        data = JSON.parse(JSON.generate(body)).fetch("data")
        product = @report[:products].find { |item| item[:id] == data.dig("relationships", "subscription", "data", "id") }
        raise "Simulated Apple rejection" if @fail_monthly && product == @report[:products].first && data.dig("attributes", "duration") == "THREE_DAYS"
        product[:introductory_offers] << { id: "new-#{@calls.length}", territory: data.dig("relationships", "territory", "data", "id"), attributes: data.fetch("attributes") }
      end
      {}
    end
  end

  def apply(operations = plan)
    snapshot = Marshal.load(Marshal.dump(@report))
    AppStoreBilling.apply_trial(plan: operations, report: snapshot, api: api, readback: -> { Marshal.load(Marshal.dump(@report)) })
  end

  def offer(duration: "ONE_WEEK", territory: "USA", mode: "FREE_TRIAL")
    { id: "old-offer", territory: territory, attributes: { "duration" => duration, "offerMode" => mode, "numberOfPeriods" => 1, "startDate" => "2026-04-24", "endDate" => nil } }
  end

  def plan = AppStoreBilling.trial_plan(report: @report, today: "2026-10-30")

  def test_replaces_only_introductory_offer_metadata_and_never_prices_or_purchases
    @report[:products].first[:introductory_offers] << offer
    operations = plan
    assert_equal ["old-offer"], operations.first[:remove_offer_ids]
    assert operations.all? { |item| item[:create] && item[:duration] == "THREE_DAYS" && item[:territory_count] == 3 }
    apply(operations)
    assert_equal 3, @calls.length
    assert @calls.first[0] == :post, "The empty annual configuration must be proven before replacing a live offer"
    assert @calls.all? { |method, path| %i[post delete].include?(method) && path.start_with?("subscriptionIntroductoryOffers") }
    @calls.select { |method,| method == :post }.each do |_, _, body|
      data = body.fetch(:data)
      assert_equal "THREE_DAYS", data[:attributes][:duration]
      assert_equal "FREE_TRIAL", data[:attributes][:offerMode]
      assert_equal 1, data[:attributes][:numberOfPeriods]
      refute data[:relationships].key?(:subscriptionPricePoint)
      refute data[:relationships].key?(:territory)
    end
  end

  def test_configured_global_trial_is_idempotent
    @report[:products].each { |product| product[:introductory_offers] << offer(duration: "THREE_DAYS", territory: nil) }
    apply
    assert_empty @calls
  end

  def test_expired_historical_offer_is_preserved
    historical = offer
    historical[:attributes]["endDate"] = "2026-05-01"
    @report[:products].first[:introductory_offers] << historical
    assert_empty plan.first[:remove_offer_ids]
  end

  def test_unapproved_and_unavailable_products_fail_before_mutation
    @report[:products].first[:attributes]["state"] = "READY_TO_SUBMIT"
    assert_raises(RuntimeError) { plan }
    @report[:products].first[:attributes]["state"] = "APPROVED"
    @report[:products].first[:availability][:territories] = []
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

  def test_nonfree_promotion_requires_inspection_and_duplicates_are_repaired
    @report[:products].first[:introductory_offers] << offer(mode: "PAY_UP_FRONT")
    assert_raises(RuntimeError) { plan }
    first = offer(duration: "THREE_DAYS", territory: nil)
    second = first.merge(id: "duplicate")
    @report[:products].first[:introductory_offers] = [first, second]
    assert_equal 2, plan.first[:remove_offer_ids].length
    assert plan.first[:create]
  end

  def test_partial_failure_restores_original_monthly_offer
    @report[:products].first[:introductory_offers] << offer
    @fail_monthly = true
    assert_raises(RuntimeError) { apply }
    monthly = @report[:products].first[:introductory_offers]
    assert_equal 1, monthly.length
    assert_equal "ONE_WEEK", monthly.first[:attributes]["duration"]
    assert_equal "USA", monthly.first[:territory]
    refute plan.last[:create]
  end

  def test_malformed_complete_plan_cannot_partially_mutate
    invalid = plan
    invalid.last[:subscription_id] = "not-the-inspected-product"
    assert_raises(RuntimeError) { apply(invalid) }
    assert_empty @calls
  end

  def test_apple_can_expand_global_trial_into_exact_territory_coverage
    @report[:products].each do |product|
      product[:introductory_offers] = product[:availability][:territories].map { |territory| offer(duration: "THREE_DAYS", territory: territory).merge(id: territory) }
    end
    apply
    assert_empty @calls
  end

  def test_pagination_cannot_loop_and_requests_cannot_send_credentials_off_apple
    assert_raises(RuntimeError) { AppStoreBilling.pages("first", api: ->(*) { { "data" => [], "links" => { "next" => "first" } } }) }
    assert_raises(RuntimeError) { AppStoreBilling.request(token: "not-a-secret", method: :get, path: "https://example.com/v1/capture") }
  end
end

AppStoreBillingTest.run!
