# frozen_string_literal: true

require "cgi"

module PaperSurveyor
  # OpenAlex titles and abstracts contain inline HTML (e.g. <i>Escherichia coli</i>
  # for species names, <sub>/<sup> for chem/math, HTML entities like &amp;).
  # Two helpers:
  #   - `to_plain`    strips all HTML and decodes entities (for topic titles)
  #   - `to_markdown` converts simple tags to Markdown equivalents (for post body)
  module TextCleaner
    HTML_TAG_RX = /<\/?[a-zA-Z][a-zA-Z0-9]*(?:\s[^>]*)?>/

    module_function

    def to_plain(text)
      return nil if text.nil?
      decoded = CGI.unescapeHTML(text.to_s)
      decoded.gsub(HTML_TAG_RX, "").gsub(/\s+/, " ").strip
    end

    def to_markdown(text)
      return nil if text.nil?
      out = CGI.unescapeHTML(text.to_s)
      out = out.gsub(%r{<(i|em)>(.*?)</\1>}im) { "_#{$2}_" }
      out = out.gsub(%r{<(b|strong)>(.*?)</\1>}im) { "**#{$2}**" }
      out = out.gsub(%r{<sub>(.*?)</sub>}im) { "~#{$1}~" }
      out = out.gsub(%r{<sup>(.*?)</sup>}im) { "^#{$1}^" }
      out.gsub(HTML_TAG_RX, "").gsub(/[ \t]+/, " ").strip
    end
  end
end
