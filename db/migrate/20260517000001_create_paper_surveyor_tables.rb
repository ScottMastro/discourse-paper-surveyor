# frozen_string_literal: true

class CreatePaperSurveyorTables < ActiveRecord::Migration[7.2]
  def change
    create_table :paper_surveyor_seen_papers do |t|
      t.string :openalex_id, null: false
      t.string :doi
      t.string :status, null: false, default: "pending"
      # pending | filtered_out | irrelevant | posted | error
      t.float :relevance_score
      t.integer :topic_id
      t.integer :upload_id
      t.text :error_message
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index :paper_surveyor_seen_papers, :openalex_id, unique: true
    add_index :paper_surveyor_seen_papers, :doi
    add_index :paper_surveyor_seen_papers, :status

    create_table :paper_surveyor_backfill_runs do |t|
      t.string :status, null: false, default: "queued"
      # queued | running | completed | failed | cancelled
      t.date :from_date, null: false
      t.date :to_date, null: false
      t.string :search_query
      t.boolean :dry_run, null: false, default: false
      t.integer :scanned_count, default: 0
      t.integer :passed_filter_count, default: 0
      t.integer :relevant_count, default: 0
      t.integer :posted_count, default: 0
      t.integer :error_count, default: 0
      t.string :cursor
      t.text :error_message
      t.integer :triggered_by_user_id
      t.timestamps
    end
    add_index :paper_surveyor_backfill_runs, :status
  end
end
