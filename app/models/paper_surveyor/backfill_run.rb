# frozen_string_literal: true

module PaperSurveyor
  class BackfillRun < ActiveRecord::Base
    self.table_name = "paper_surveyor_backfill_runs"

    STATUSES = %w[queued running completed failed cancelled].freeze

    validates :status, inclusion: { in: STATUSES }
    validates :from_date, :to_date, presence: true

    def cancelled?
      reload.status == "cancelled"
    end
  end
end
