# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module PaperSurveyor
  # Thin wrapper around the OpenAlex /works endpoint with cursor pagination.
  # OpenAlex docs: https://docs.openalex.org/
  class OpenAlexClient
    BASE_URL = "https://api.openalex.org"
    PER_PAGE = 200

    class Error < StandardError; end

    def initialize(mailto: SiteSetting.paper_surveyor_openalex_mailto)
      @mailto = mailto.presence
    end

    # Yields each work hash. Walks the cursor automatically.
    #
    # filters - hash of OpenAlex filter key => value (already-formatted)
    # search  - free text search (title + abstract)
    # cursor  - resume from a previous cursor (for backfill restart)
    def each_work(filters:, search: nil, cursor: "*")
      return enum_for(:each_work, filters: filters, search: search, cursor: cursor) unless block_given?

      loop do
        page = fetch_page(filters: filters, search: search, cursor: cursor)
        (page["results"] || []).each { |w| yield w }

        cursor = page.dig("meta", "next_cursor")
        break if cursor.blank? || (page["results"] || []).empty?
      end
    end

    def fetch_page(filters:, search: nil, cursor: "*")
      params = {
        "filter" => filters.map { |k, v| "#{k}:#{v}" }.join(","),
        "per-page" => PER_PAGE,
        "cursor" => cursor,
      }
      params["search"] = search if search.present?
      params["mailto"] = @mailto if @mailto

      uri = URI("#{BASE_URL}/works")
      uri.query = URI.encode_www_form(params)

      response = http_get(uri)
      JSON.parse(response.body)
    end

    def fetch_work(openalex_id)
      uri = URI("#{BASE_URL}/works/#{openalex_id}")
      uri.query = URI.encode_www_form(mailto: @mailto) if @mailto
      JSON.parse(http_get(uri).body)
    end

    private

    def http_get(uri)
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = user_agent
      req["Accept"] = "application/json"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 30) do |http|
        http.request(req)
      end

      raise Error, "OpenAlex #{response.code}: #{response.body[0, 200]}" unless response.is_a?(Net::HTTPSuccess)
      response
    end

    def user_agent
      base = "paper-surveyor/#{PaperSurveyor::VERSION rescue "0.1"} (Discourse plugin)"
      @mailto ? "#{base}; mailto:#{@mailto}" : base
    end
  end
end
