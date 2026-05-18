# frozen_string_literal: true

class AddTitleKeyToPaperSurveyorSeenPapers < ActiveRecord::Migration[7.2]
  def change
    add_column :paper_surveyor_seen_papers, :title_key, :string
    add_index :paper_surveyor_seen_papers, :title_key
  end
end
