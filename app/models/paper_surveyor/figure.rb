# frozen_string_literal: true

module PaperSurveyor
  class Figure < ActiveRecord::Base
    self.table_name = "paper_surveyor_figures"

    KINDS = %w[unknown figure table boilerplate other].freeze

    belongs_to :seen_paper,
               class_name: "PaperSurveyor::SeenPaper",
               foreign_key: :seen_paper_id
    belongs_to :upload, class_name: "::Upload"

    validates :sequence_index, presence: true
    validates :kind, inclusion: { in: KINDS }

    scope :usable, -> { where(kind: "figure") }
  end
end
