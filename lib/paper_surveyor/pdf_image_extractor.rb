# frozen_string_literal: true

require "open3"
require "tmpdir"

module PaperSurveyor
  # Extracts every embedded raster image from a PDF using `pdfimages`
  # (poppler-utils, ships alongside pdftotext). Returns an ordered list of
  # hashes: { sequence_index:, page:, path: }. Caller cleans up `path`.
  #
  # We do almost no filtering here — the LLM annotator decides what's a real
  # figure vs boilerplate. The only filter is a tiny minimum-size cutoff to
  # avoid wasting annotation tokens on 1×1 pixel artifacts.
  module PdfImageExtractor
    MIN_BYTES = 4_000 # < 4 KB images are almost always artifacts/spacers

    Image = Struct.new(:sequence_index, :page, :path, keyword_init: true)

    module_function

    def extract(pdf_path)
      return [] unless File.exist?(pdf_path)

      out_dir = Dir.mktmpdir("paper-imgs")
      prefix = File.join(out_dir, "img")

      _, stderr, status = Open3.capture3("pdfimages", "-png", pdf_path, prefix)
      unless status.success?
        Rails.logger.warn("[paper-surveyor] pdfimages failed: #{stderr.lines.last(2).join}")
        return []
      end

      pages_by_index = page_index_map(pdf_path)

      Dir.glob("#{prefix}-*.png").sort.map.with_index do |path, idx|
        next if File.size(path) < MIN_BYTES
        Image.new(
          sequence_index: idx,
          page: pages_by_index[idx],
          path: path,
        )
      end.compact
    rescue Errno::ENOENT
      Rails.logger.warn("[paper-surveyor] pdfimages binary not installed")
      []
    end

    # Run `pdfimages -list` to learn which page each image came from.
    # Returns { sequence_index => page_number }.
    def page_index_map(pdf_path)
      stdout, _stderr, status = Open3.capture3("pdfimages", "-list", pdf_path)
      return {} unless status.success?

      map = {}
      stdout.each_line.with_index do |line, i|
        # header rows: 2 lines, then data rows like "  page   num   ..."
        next if i < 2
        parts = line.split
        next if parts.length < 2
        page = parts[0].to_i
        num = parts[1].to_i
        map[num] = page
      end
      map
    end
  end
end
