# frozen_string_literal: true

module PaperSurveyor
  # Creates a Discourse topic for a paper. Idempotent at the SeenPaper layer
  # (callers should not invoke this twice for the same OpenAlex ID).
  #
  # Post structure:
  #   <citation blockquote>
  #   <quick-links row>
  #   ---
  #   <summary from LLM (figures already embedded inline via Markdown)>
  #   <[details] Original abstract>
  #   ---
  #   <footer>
  class Publisher
    def publish(work:, summary:, category_id:, abstract: nil)
      category_id = category_id.to_i
      return nil if category_id <= 0

      user = User.find_by(username: SiteSetting.paper_surveyor_poster_username) || Discourse.system_user
      title = sanitize_title(work["title"].to_s)
      raw = build_body(work: work, summary: summary, abstract: abstract)
      tags = SiteSetting.paper_surveyor_topic_tags.to_s.split("|").reject(&:blank?)

      creator = PostCreator.new(
        user,
        title: title,
        raw: raw,
        category: category_id,
        tags: tags,
        skip_validations: true,
      )
      post = creator.create!
      post.topic
    end

    private

    def sanitize_title(title)
      cleaned = TextCleaner.to_plain(title) || ""
      cleaned = cleaned[0, 250] if cleaned.length > 250
      cleaned.presence || "Untitled paper"
    end

    def build_body(work:, summary:, abstract:)
      sections = []

      sections << CitationFormatter.citation(work)

      links = CitationFormatter.links_row(work)
      sections << links if links

      sections << "---"
      sections << summary.to_s.strip if summary.present?

      if abstract.present?
        sections << "[details=\"Original abstract\"]\n#{abstract.strip}\n[/details]"
      end

      sections << "---"
      sections << I18n.t("paper_surveyor.post_template.footer")
      sections.compact.reject(&:empty?).join("\n\n")
    end
  end
end
