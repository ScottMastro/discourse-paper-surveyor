# frozen_string_literal: true

require "net/http"
require "tempfile"

module PaperSurveyor
  # Downloads a PDF (if licensing allows) and stores it via Discourse's
  # UploadCreator so it can be attached to the topic like any other file.
  #
  # Returns an Upload, or nil if the PDF was unavailable or rejected
  # (closed access, too large, fetch error, bad content type).
  class PdfFetcher
    class TooLargeError < StandardError; end
    class BadContentTypeError < StandardError; end

    def fetch_and_store(work)
      return nil unless SiteSetting.paper_surveyor_store_pdfs

      oa = work["open_access"] || {}
      status = oa["oa_status"]
      url = oa["oa_url"] || work.dig("best_oa_location", "pdf_url")

      allowed_statuses = SiteSetting.paper_surveyor_pdf_oa_statuses.to_s.split("|")
      return nil if url.blank? || !allowed_statuses.include?(status)

      max_bytes = SiteSetting.paper_surveyor_pdf_max_mb.to_i * 1024 * 1024
      filename = File.basename(URI.parse(url).path.presence || "paper.pdf")
      filename = "paper.pdf" unless filename.end_with?(".pdf")

      tempfile = download(url, max_bytes: max_bytes)
      return nil unless tempfile

      UploadCreator.new(tempfile, filename, type: "paper_surveyor").create_for(Discourse.system_user.id)
    rescue TooLargeError, BadContentTypeError => e
      Rails.logger.info("[paper-surveyor] skipping PDF for #{work["id"]}: #{e.message}")
      nil
    rescue => e
      Rails.logger.warn("[paper-surveyor] PDF fetch failed for #{work["id"]}: #{e.message}")
      nil
    end

    private

    def download(url, max_bytes:)
      uri = URI.parse(url)
      tempfile = Tempfile.new(["paper", ".pdf"], binmode: true)
      written = 0

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 60) do |http|
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = user_agent
        req["Accept"] = "application/pdf"

        http.request(req) do |response|
          # Follow at most one redirect (HTTPS only) — academic CDNs love them.
          if response.is_a?(Net::HTTPRedirection)
            tempfile.close!
            return download(response["location"], max_bytes: max_bytes)
          end

          unless response.is_a?(Net::HTTPSuccess)
            tempfile.close!
            return nil
          end

          ctype = response["content-type"].to_s
          raise BadContentTypeError, "expected PDF, got #{ctype}" unless ctype.include?("pdf")

          response.read_body do |chunk|
            written += chunk.bytesize
            raise TooLargeError, "exceeds #{max_bytes} bytes" if written > max_bytes
            tempfile.write(chunk)
          end
        end
      end

      tempfile.rewind
      tempfile
    end

    def user_agent
      mailto = SiteSetting.paper_surveyor_openalex_mailto.presence
      base = "paper-surveyor/0.1 (Discourse plugin)"
      mailto ? "#{base}; mailto:#{mailto}" : base
    end
  end
end
