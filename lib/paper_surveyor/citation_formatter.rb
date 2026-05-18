# frozen_string_literal: true

module PaperSurveyor
  # Builds a human-readable citation block + a "quick links" row for the
  # top of an auto-generated topic. Uses OpenAlex's display names verbatim
  # (no surname/initials reformatting — too unreliable across cultures).
  module CitationFormatter
    AUTHOR_LIMIT = 6 # truncate to "et al." beyond this

    module_function

    # Returns the Markdown citation block (a blockquote with 1-2 lines).
    def citation(work)
      authors = format_authors(work)
      year = extract_year(work)
      title = TextCleaner.to_markdown(work["title"]).to_s
      source = TextCleaner.to_plain(work.dig("primary_location", "source", "display_name"))
      doi = work["doi"]

      heading_parts = []
      heading_parts << "**#{authors}** " if authors.present?
      heading_parts << "**(#{year}).**" if year
      heading = heading_parts.join

      title_line = title.present? ? "_#{title}._" : nil
      tail_parts = []
      tail_parts << "_#{source}_." if source.present?
      tail_parts << doi_link(doi) if doi.present?
      tail_line = tail_parts.join(" ")

      lines = [heading, title_line, tail_line].compact.reject(&:empty?)
      lines.map { |l| "> #{l}" }.join("  \n")
    end

    # Returns the Markdown quick-links row, or nil if there's nothing to link.
    # Always links to the publisher's external PDF (when available) — we never
    # surface our own stored copy.
    def links_row(work)
      parts = []

      landing = work.dig("primary_location", "landing_page_url")
      if landing.present?
        source_name = work.dig("primary_location", "source", "display_name") || "source"
        parts << ":link: [Read on #{source_name}](#{landing})"
      end

      pdf_url = work.dig("best_oa_location", "pdf_url") || work.dig("primary_location", "pdf_url")
      parts << ":page_facing_up: [PDF](#{pdf_url})" if pdf_url.present?

      if (oa_id = work["id"])
        parts << ":globe_with_meridians: [OpenAlex](#{oa_id})"
      end

      parts.empty? ? nil : parts.join(" · ")
    end

    def format_authors(work)
      names = Array(work["authorships"]).map { |a| a.dig("author", "display_name") }.compact
      return nil if names.empty?

      if names.length > AUTHOR_LIMIT
        names.first(AUTHOR_LIMIT - 1).join(", ") + ", et al."
      else
        names.join(", ")
      end
    end

    def extract_year(work)
      date = work["publication_date"].to_s
      return nil unless date =~ /\A(\d{4})/
      Regexp.last_match(1)
    end

    def doi_link(doi)
      stripped = doi.to_s.sub(%r{\Ahttps?://(?:dx\.)?doi\.org/}, "")
      "[#{stripped}](https://doi.org/#{stripped})"
    end
  end
end
