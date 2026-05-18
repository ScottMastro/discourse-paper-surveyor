# frozen_string_literal: true

require "open3"

module PaperSurveyor
  # Extract plain text from a PDF, with optional reference-list trimming
  # to save tokens before sending to an LLM.
  module PdfTextExtractor
    # Headings that signal "everything below is bibliography." Matched at the
    # start of a line, case-insensitive, allowing surrounding punctuation/whitespace.
    REFERENCE_HEADINGS = %w[
      references
      bibliography
      literature\ cited
      works\ cited
      reference\ list
      cited\ literature
    ].freeze

    REFERENCE_HEADING_RX =
      /^\s*(?:\d+\.?\s*)?(?:#{REFERENCE_HEADINGS.join("|")})\s*$/i

    module_function

    def extract(file_path, strip_references: true)
      return nil unless File.exist?(file_path)

      stdout, _stderr, status = Open3.capture3("pdftotext", "-layout", "-q", file_path, "-")
      return nil unless status.success?

      text = stdout.to_s
      text = strip_references_section(text) if strip_references
      text.strip.presence
    rescue Errno::ENOENT
      Rails.logger.warn("[paper-surveyor] pdftotext not installed; skipping text extraction")
      nil
    end

    # Drop everything from the last References-style heading onward.
    # "Last" because some papers cite References in the body (e.g. table headers).
    def strip_references_section(text)
      lines = text.split("\n")
      cut_index = nil
      lines.each_with_index { |line, i| cut_index = i if line =~ REFERENCE_HEADING_RX }
      return text unless cut_index

      kept = lines.first(cut_index).join("\n")
      # Only trim if the references section is meaningfully large — guards against
      # false positives on a stray heading in the body.
      dropped_chars = text.length - kept.length
      dropped_chars > 1_000 ? kept : text
    end
  end
end
