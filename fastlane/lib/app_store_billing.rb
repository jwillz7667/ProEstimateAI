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
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) { |http| http.request(request) }
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
        points = prices.fetch("included", []).select { |record| record["type"] == "subscriptionPricePoints" }.to_h { |record| [record.fetch("id"), record.fetch("attributes")] }
        { id: id, group_id: group["id"], attributes: attributes, availability: { id: availability["id"], attributes: availability["attributes"], territories: territories }, introductory_offers: offers, us_prices: prices.fetch("data").map { |price| { attributes: price["attributes"], price_point: points[price.dig("relationships", "subscriptionPricePoint", "data", "id")] } } }
      end
    end
    raise "Expected exactly the two Pro subscription products" unless products.map { |product| product[:attributes]["productId"] }.sort == PRODUCTS.sort
    { app_id: app_id, subscription_groups: groups.map { |group| { id: group["id"], attributes: group["attributes"] } }, products: products }
  end

  def self.trial_plan(report:, today: Date.today.iso8601)
    products = report.fetch(:products)
    raise "Trial updates require exactly the two Pro products" unless products.map { |product| product[:attributes]["productId"] }.sort == PRODUCTS.sort
    raise "Both products must share one subscription group" unless products.map { |product| product[:group_id] }.uniq.length == 1
    products.map do |product|
      raise "Only approved, available subscriptions may receive the trial" unless product[:attributes]["state"] == "APPROVED" && !product[:availability][:territories].empty?
      current = product[:introductory_offers].reject { |offer| offer[:attributes]["endDate"] && offer[:attributes]["endDate"] < today }
      eligible = current.select do |offer|
        attributes = offer[:attributes]
        attributes["duration"] == "THREE_DAYS" && attributes["offerMode"] == "FREE_TRIAL" && attributes["numberOfPeriods"] == 1 && attributes["endDate"].nil? && (attributes["startDate"].nil? || attributes["startDate"] <= today)
      end
      covered = product[:availability][:territories].all? do |territory|
        eligible.count { |offer| offer[:territory].nil? || offer[:territory] == territory } == 1
      end
      configured = covered && eligible.length == current.length
      conflicts = configured ? [] : current
      raise "Unexpected non-free introductory promotion; inspect before changing" unless conflicts.all? { |offer| offer[:attributes]["offerMode"] == "FREE_TRIAL" }
      {
        subscription_id: product[:id], product_id: product[:attributes]["productId"],
        remove_offer_ids: conflicts.map { |offer| offer[:id] },
        create: !configured, start_date: today,
        offer_mode: "FREE_TRIAL", duration: "THREE_DAYS", number_of_periods: 1,
        scope: "all_available_territories", territory_count: product[:availability][:territories].length
      }
    end
  end

  def self.stable_configuration(report)
    report.fetch(:products).map do |product|
      { id: product[:id], product_id: product[:attributes]["productId"], group: product[:group_id], availability: product[:availability], prices: product[:us_prices] }
    end.sort_by { |product| product[:id] }
  end

  def self.apply_trial(plan:, report:, api:, readback: nil)
    today = plan.first&.fetch(:start_date)
    raise "Trial plan does not match the inspected Apple configuration" unless plan == trial_plan(report: report, today: today)
    refresh = readback || -> { inspect(app_id: report.fetch(:app_id), api: api) }
    baseline = stable_configuration(report)
    current_report = report
    # Prove a new conflict-free offer first, before replacing a live offer.
    plan.sort_by { |item| item.fetch(:remove_offer_ids).length }.each do |item|
      next unless item[:create] || !item[:remove_offer_ids].empty?
      current_item = trial_plan(report: current_report, today: today).find { |entry| entry[:product_id] == item[:product_id] }
      raise "Apple introductory offers changed after inspection" unless current_item == item
      previous = current_report[:products].find { |product| product[:id] == item[:subscription_id] }
      removed = previous[:introductory_offers].select { |offer| item[:remove_offer_ids].include?(offer[:id]) }
      item.fetch(:remove_offer_ids).each { |id| api.call(:delete, "subscriptionIntroductoryOffers/#{id}") }
      begin
        if item.fetch(:create)
          api.call(:post, "subscriptionIntroductoryOffers", {
            data: {
              type: "subscriptionIntroductoryOffers",
              attributes: { duration: "THREE_DAYS", offerMode: "FREE_TRIAL", numberOfPeriods: 1 },
              relationships: { subscription: { data: { type: "subscriptions", id: item.fetch(:subscription_id) } } }
            }
          })
        end
      rescue StandardError => original_error
        # A timed-out POST may have succeeded. Inspect before compensating so
        # retries cannot create duplicate offers. Restore a removed offer only
        # when Apple confirms that this product has no offer at all.
        after_error = refresh.call
        observed = after_error[:products].find { |product| product[:id] == item[:subscription_id] }
        if observed[:introductory_offers].empty?
          removed.each do |offer|
            relationships = { subscription: { data: { type: "subscriptions", id: item[:subscription_id] } } }
            relationships[:territory] = { data: { type: "territories", id: offer[:territory] } } if offer[:territory]
            attributes = offer[:attributes].select { |key, _| %w[duration offerMode numberOfPeriods endDate].include?(key) }
            api.call(:post, "subscriptionIntroductoryOffers", { data: { type: "subscriptionIntroductoryOffers", attributes: attributes, relationships: relationships } })
          end
          raise original_error
        end
        recovered = trial_plan(report: after_error, today: today).find { |entry| entry[:product_id] == item[:product_id] }
        raise original_error if recovered[:create] || !recovered[:remove_offer_ids].empty?
      end
      current_report = refresh.call
      raise "Prices or sale availability changed during trial setup" unless stable_configuration(current_report) == baseline
      checked = trial_plan(report: current_report, today: today).find { |entry| entry[:product_id] == item[:product_id] }
      raise "Apple has not confirmed the requested three-day coverage" if checked[:create] || !checked[:remove_offer_ids].empty?
    end
    current_report
  end
end
