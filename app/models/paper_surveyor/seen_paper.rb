# frozen_string_literal: true

module PaperSurveyor
  class SeenPaper < ActiveRecord::Base
    self.table_name = "paper_surveyor_seen_papers"

    STATUSES = %w[pending filtered_out irrelevant duplicate posted error].freeze

    validates :openalex_id, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }

    # Normalized title used to detect the same paper indexed under different
    # OpenAlex IDs (e.g. Zenodo "version" vs "all versions" DOIs).
    def self.title_key_for(title)
      return nil if title.blank?
      TextCleaner.to_plain(title).to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip.presence
    end
  end
end
