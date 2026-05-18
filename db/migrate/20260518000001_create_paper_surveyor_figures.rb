# frozen_string_literal: true

class CreatePaperSurveyorFigures < ActiveRecord::Migration[7.2]
  def change
    create_table :paper_surveyor_figures do |t|
      t.integer :seen_paper_id, null: false
      t.integer :upload_id, null: false
      t.integer :sequence_index, null: false
      t.integer :page
      t.string :kind, null: false, default: "unknown"
      # unknown | figure | table | boilerplate | other
      t.text :description
      t.string :annotated_with
      t.timestamps
    end
    add_index :paper_surveyor_figures, :seen_paper_id
    add_index :paper_surveyor_figures, :upload_id
    add_index :paper_surveyor_figures, :kind
  end
end
