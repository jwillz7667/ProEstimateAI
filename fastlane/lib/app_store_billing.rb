require "json"
require "net/http"
require "uri"

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
end
