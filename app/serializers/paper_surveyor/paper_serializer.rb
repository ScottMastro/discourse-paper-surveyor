# frozen_string_literal: true

module PaperSurveyor
  class PaperSerializer < ApplicationSerializer
    attributes :id,
               :openalex_id,
               :doi,
               :title,
               :status,
               :relevance_score,
               :route,
               :work_type,
               :publication_date,
               :topic_id,
               :topic_url,
               :upload_id,
               :error_message,
               :created_at

    def title
      object.metadata&.dig("title") || "(no title)"
    end

    def route
      object.metadata&.dig("route")
    end

    def work_type
      object.metadata&.dig("work_type")
    end

    def publication_date
      object.metadata&.dig("publication_date")
    end

    def topic_url
      return nil unless object.topic_id
      "/t/#{object.topic_id}"
    end
  end
end
