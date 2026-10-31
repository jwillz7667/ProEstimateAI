require "json"
require "net/http"
require "uri"
require "date"

module AppStoreBilling
  PRODUCTS = %w[proestimate.pro.monthly proestimate.pro.annual].freeze
  BASE = "https://api.appstoreconnect.apple.com/v1/".freeze

  def self.request(token:, method:, path:, body: nil)
    uri = URI.join(BASE, path)
    raise "Unexpected Apple API address" unless uri.scheme == "https" && uri.host == "api.appstoreconnect.apple.com" && uri.path.start_with?("/v1/")
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method)
    request = klass.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body) if body
    attempts = 0
    response = loop do
      result = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) { |http| http.request(request) }
      # A 429 rejects the operation, so retrying it cannot duplicate an
      # accepted offer. Other POST failures are reconciled by readback below.
      break result unless result.code.to_i == 429 && attempts < 4
      attempts += 1
      delay = Float(result["Retry-After"], exception: false) || (2**attempts)
      sleep [[delay, 1].max, 60].min
    end
    parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
    unless response.is_a?(Net::HTTPSuccess)
      details = parsed.fetch("errors", []).map { |error| error["detail"] }.join("; ")
      raise "Apple billing request failed (#{response.code}): #{details}"
    end
    parsed
  end

  def self.pages(path, api:)
    records = []
    seen = {}
    while path
      raise "Repeated Apple pagination address" if seen[path]
      seen[path] = true
      page = api.call(:get, path)
      records.concat(page.fetch("data"))
      path = page.dig("links", "next")
    end
    records
  end

  def self.inspect(app_id:, api:)
    groups = pages("apps/#{app_id}/subscriptionGroups?limit=200", api: api)
    products = groups.flat_map do |group|
      pages("subscriptionGroups/#{group.fetch('id')}/subscriptions?limit=200", api: api).filter_map do |subscription|
        attributes = subscription.fetch("attributes")
        next unless PRODUCTS.include?(attributes["productId"])
        id = subscription.fetch("id")
        offers = pages("subscriptions/#{id}/introductoryOffers?include=territory&limit=200", api: api).map do |offer|
          { id: offer["id"], attributes: offer["attributes"], territory: offer.dig("relationships", "territory", "data", "id") }
        end
        availability = api.call(:get, "subscriptions/#{id}/subscriptionAvailability").fetch("data")
        territories = pages("subscriptionAvailabilities/#{availability.fetch('id')}/availableTerritories?limit=200", api: api).map { |territory| territory.fetch("id") }.sort
        prices = api.call(:get, "subscriptions/#{id}/prices?filter[territory]=USA&include=subscriptionPricePoint&limit=200")
        all_prices = pages("subscriptions/#{id}/prices?include=subscriptionPricePoint&limit=200", api: api).map do |price|
          { id: price.fetch("id"), attributes: price.fetch("attributes"), price_point: price.dig("relationships", "subscriptionPricePoint", "data") }
        end.sort_by { |price| price[:id] }
        points = prices.fetch("included", []).select { |record| record["type"] == "subscriptionPricePoints" }.to_h { |record| [record.fetch("id"), record.fetch("attributes")] }
        { id: id, group_id: group["id"], attributes: attributes, availability: { id: availability["id"], attributes: availability["attributes"], territories: territories }, introductory_offers: offers, prices: all_prices, us_prices: prices.fetch("data").map { |price| { attributes: price["attributes"], price_point: points[price.dig("relationships", "subscriptionPricePoint", "data", "id")] } } }
      end
    end
    raise "Expected exactly the two Pro subscription products" unless products.map { |product| product[:attributes]["productId"] }.sort == PRODUCTS.sort
    { app_id: app_id, subscription_groups: groups.map { |group| { id: group["id"], attributes: group["attributes"] } }, products: products }
  end

  def self.trial_plan(report:, today: Date.today.iso8601)
    Date.iso8601(today)
    products = report.fetch(:products)
    raise "Trial updates require exactly the two Pro products" unless products.map { |product| product[:attributes]["productId"] }.sort == PRODUCTS.sort
    raise "Both products must share one subscription group" unless products.map { |product| product[:group_id] }.uniq.length == 1
    raise "Subscription IDs must be distinct" unless products.map { |product| product[:id] }.uniq.length == 2
    products.map do |product|
      territories = product.fetch(:availability).fetch(:territories)
      raise "Only approved, available subscriptions may receive the trial" unless product[:attributes]["state"] == "APPROVED" && !territories.empty?
      raise "Availability must contain unique territories including USA" unless territories.uniq == territories && territories.include?("USA")
      current = current_offers(product, today)
      globals = current.select { |offer| offer[:territory].nil? }
      # Retain an existing global three-day offer if Apple ever returns one,
      # but never create one: the live API requires an explicit territory.
      raise "Unexpected global offer; inspect before changing" unless globals.length <= 1 && globals.all? { |offer| exact_trial?(offer, today) }
      operations = territories.sort.map do |territory|
        applicable = current.select { |offer| offer[:territory].nil? || offer[:territory] == territory }
        raise "Unexpected non-free introductory promotion; inspect before changing" unless applicable.all? { |offer| offer[:attributes]["offerMode"] == "FREE_TRIAL" }
        retained = applicable.select { |offer| exact_trial?(offer, today) }.min_by { |offer| [offer[:territory].nil? ? 0 : 1, offer[:id]] }
        conflicts = applicable.reject { |offer| retained && offer[:id] == retained[:id] }
        {
          territory: territory, retained_offer_id: retained && retained[:id],
          remove_offer_ids: conflicts.map { |offer| offer[:id] }.sort,
          create: retained.nil?
        }
      end
      {
        subscription_id: product[:id], product_id: product[:attributes]["productId"],
        remove_offer_ids: operations.flat_map { |operation| operation[:remove_offer_ids] }.uniq.sort,
        create: operations.any? { |operation| operation[:create] }, start_date: today,
        offer_mode: "FREE_TRIAL", duration: "THREE_DAYS", number_of_periods: 1,
        scope: "all_available_territories", territory_count: territories.length,
        territories: operations
      }
    end
  end

  def self.current_offers(product, today)
    product.fetch(:introductory_offers).reject { |offer| offer[:attributes]["endDate"] && offer[:attributes]["endDate"] < today }
  end

  def self.summary(report:, today: Time.now.utc.strftime("%Y-%m-%d"))
    {
      app_id: report[:app_id],
      products: report.fetch(:products).map do |product|
        territories = product.fetch(:availability).fetch(:territories)
        missing = territories.reject { |territory| territory_configured?(product, territory, today) }
        {
          id: product[:id], product_id: product[:attributes]["productId"], state: product[:attributes]["state"],
          group_id: product[:group_id], available_countries: territories.length,
          three_day_countries: territories.length - missing.length, missing_countries: missing,
          offer_count: product[:introductory_offers].length,
          base_price_count: product.fetch(:prices, []).length,
          us_prices: product[:us_prices].map { |price| price[:price_point] && price[:price_point]["customerPrice"] }
        }
      end
    }
  end

  def self.exact_trial?(offer, today)
    attributes = offer.fetch(:attributes)
    attributes["duration"] == "THREE_DAYS" && attributes["offerMode"] == "FREE_TRIAL" &&
      attributes["numberOfPeriods"] == 1 && attributes["endDate"].nil? &&
      (attributes["startDate"].nil? || attributes["startDate"] <= today)
  end

  def self.territory_configured?(product, territory, today)
    offers = current_offers(product, today).select { |offer| offer[:territory].nil? || offer[:territory] == territory }
    offers.length == 1 && exact_trial?(offers.first, today)
  end

  def self.stable_configuration(report)
    report.fetch(:products).map do |product|
      { id: product[:id], product_id: product[:attributes]["productId"], group: product[:group_id], availability: product[:availability], prices: product[:prices] || product[:us_prices] }
    end.sort_by { |product| product[:id] }
  end

  def self.apply_trial(plan:, report:, api:, readback: nil)
    raise "Trial updates require a complete two-product plan" unless plan.is_a?(Array) && plan.length == 2 && plan.all? { |item| item.is_a?(Hash) && item[:start_date].is_a?(String) }
    today = plan.first.fetch(:start_date)
    raise "Trial plan does not match the inspected Apple configuration" unless plan == trial_plan(report: report, today: today)
    refresh = readback || -> { inspect(app_id: report.fetch(:app_id), api: api) }
    baseline = stable_configuration(report)
    current_report = report
    checked_refresh = lambda do
      fresh = refresh.call
      raise "Prices or sale availability changed during trial setup" unless stable_configuration(fresh) == baseline
      fresh
    end

    # The annual USA request proves the exact territory-scoped payload and
    # permissions before any existing monthly offer can be removed.
    %w[proestimate.pro.annual proestimate.pro.monthly].each do |product_id|
      item = plan.find { |entry| entry[:product_id] == product_id }
      expected = trial_plan(report: current_report, today: today).find { |entry| entry[:product_id] == product_id }
      raise "Apple introductory offers changed after inspection" unless expected == item
      usa = item.fetch(:territories).find { |operation| operation[:territory] == "USA" }
      if product_id.end_with?("annual") && !usa[:remove_offer_ids].empty?
        raise "Annual USA verification must not remove an existing offer"
      end
      previous = current_report.fetch(:products).find { |product| product[:id] == item[:subscription_id] }
      apply_territory(item: item, operation: usa, previous: previous, today: today, api: api, refresh: checked_refresh)
      current_report = checked_refresh.call
      observed = current_report.fetch(:products).find { |product| product[:id] == item[:subscription_id] }
      raise "Apple has not confirmed the USA three-day trial" unless territory_configured?(observed, "USA", today)

      # Continue only missing/conflicting countries. Successful country rows
      # survive a partial failure and are retained by the next inspected plan.
      fresh_item = trial_plan(report: current_report, today: today).find { |entry| entry[:product_id] == product_id }
      fresh_item.fetch(:territories).reject { |operation| operation[:territory] == "USA" }.each do |operation|
        apply_territory(item: fresh_item, operation: operation, previous: observed, today: today, api: api, refresh: checked_refresh)
      end
      current_report = checked_refresh.call
      checked = trial_plan(report: current_report, today: today).find { |entry| entry[:product_id] == product_id }
      raise "Apple has not confirmed the requested three-day coverage" if checked[:create] || !checked[:remove_offer_ids].empty?
    end
    current_report
  end

  def self.create_offer(subscription_id:, territory:, attributes:, api:)
    api.call(:post, "subscriptionIntroductoryOffers", {
      data: {
        type: "subscriptionIntroductoryOffers", attributes: attributes,
        relationships: {
          subscription: { data: { type: "subscriptions", id: subscription_id } },
          territory: { data: { type: "territories", id: territory } }
        }
      }
    })
  end

  def self.apply_territory(item:, operation:, previous:, today:, api:, refresh:)
    return unless operation[:create] || !operation[:remove_offer_ids].empty?
    territory = operation.fetch(:territory)
    removed = previous.fetch(:introductory_offers).select { |offer| operation[:remove_offer_ids].include?(offer[:id]) }
    begin
      operation.fetch(:remove_offer_ids).each { |id| api.call(:delete, "subscriptionIntroductoryOffers/#{id}") }
      if operation.fetch(:create)
        create_offer(subscription_id: item[:subscription_id], territory: territory,
                     attributes: { duration: "THREE_DAYS", offerMode: "FREE_TRIAL", numberOfPeriods: 1 }, api: api)
      end
    rescue StandardError => original_error
      # A timed-out POST may already have succeeded: never blindly create a
      # duplicate. Reconcile this country only, not unrelated country rows.
      after_error = refresh.call
      observed = after_error.fetch(:products).find { |product| product[:id] == item[:subscription_id] }
      return if territory_configured?(observed, territory, today)
      applicable = current_offers(observed, today).select { |offer| offer[:territory].nil? || offer[:territory] == territory }
      if applicable.empty? && !removed.empty?
        begin
          removed.each do |offer|
            attributes = offer[:attributes].select { |key, _| %w[duration offerMode numberOfPeriods endDate].include?(key) }
            # The former start date can be in the past; omitting it restores
            # the same offer terms starting now without backdating metadata.
            create_offer(subscription_id: item[:subscription_id], territory: territory, attributes: attributes, api: api)
          end
          confirmed = refresh.call.fetch(:products).find { |product| product[:id] == item[:subscription_id] }
          raise "Apple has not confirmed the compensating restore" unless restored_terms?(confirmed, removed, territory, today)
        rescue StandardError => restore_error
          recovered = refresh.call.fetch(:products).find { |product| product[:id] == item[:subscription_id] }
          raise "Trial replacement and compensating restore failed: #{original_error.message}; #{restore_error.message}" unless restored_terms?(recovered, removed, territory, today)
        end
      end
      raise original_error
    end
  end

  def self.restored_terms?(product, previous, territory, today)
    observed = current_offers(product, today).select { |offer| offer[:territory] == territory }
    previous.all? do |old|
      observed.any? { |offer| %w[duration offerMode numberOfPeriods endDate].all? { |key| offer[:attributes][key] == old[:attributes][key] } }
    end
  end
end
