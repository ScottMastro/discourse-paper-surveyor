# frozen_string_literal: true

class RenamePreprintSurveyorTables < ActiveRecord::Migration[7.2]
  def up
    if table_exists?(:preprint_surveyor_seen_papers) && !table_exists?(:paper_surveyor_seen_papers)
      rename_table :preprint_surveyor_seen_papers, :paper_surveyor_seen_papers
    end
    if table_exists?(:preprint_surveyor_backfill_runs) && !table_exists?(:paper_surveyor_backfill_runs)
      rename_table :preprint_surveyor_backfill_runs, :paper_surveyor_backfill_runs
    end
  end

  def down
    if table_exists?(:paper_surveyor_seen_papers) && !table_exists?(:preprint_surveyor_seen_papers)
      rename_table :paper_surveyor_seen_papers, :preprint_surveyor_seen_papers
    end
    if table_exists?(:paper_surveyor_backfill_runs) && !table_exists?(:preprint_surveyor_backfill_runs)
      rename_table :paper_surveyor_backfill_runs, :preprint_surveyor_backfill_runs
    end
  end
end
