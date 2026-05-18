# frozen_string_literal: true

module PaperSurveyor
  # Orchestrates the per-paper pipeline:
  #
  #   dedupe -> relevance LLM -> PDF fetch -> image extract + LLM annotate
  #     -> full-text extract (refs stripped) -> summarize (figures in prompt)
  #     -> publish topic to route.category.
  #
  # No figure substitution step: the summarizer is given each figure's upload
  # URL up front and embeds them via standard Markdown.
  class Pipeline
    Result = Struct.new(:seen_paper, :status, :topic, keyword_init: true)

    def initialize(dry_run: false)
      @dry_run = dry_run
    end

    def process(work, route:)
      openalex_id = work["id"].to_s.sub("https://openalex.org/", "")
      seen = SeenPaper.find_or_initialize_by(openalex_id: openalex_id)
      return Result.new(seen_paper: seen, status: :already_seen) unless seen.new_record?

      seen.doi = work["doi"]
      title = TextCleaner.to_plain(work["title"]).to_s
      title_key = SeenPaper.title_key_for(title)
      seen.title_key = title_key
      seen.metadata = {
        title: work["title"],
        publication_date: work["publication_date"],
        route: route.name,
        work_type: work["type"],
      }

      # Same paper indexed under a different OpenAlex ID? Mark as duplicate.
      if title_key.present?
        existing = SeenPaper.where(status: %w[posted duplicate], title_key: title_key)
                            .where.not(openalex_id: openalex_id)
                            .first
        if existing
          seen.status = "duplicate"
          seen.metadata = seen.metadata.merge(duplicate_of: existing.openalex_id)
          seen.save! unless @dry_run
          return Result.new(seen_paper: seen, status: :duplicate)
        end
      end

      abstract = AbstractReconstructor.call(work["abstract_inverted_index"])

      score = RelevanceChecker.new.score(title: title, abstract: abstract)
      seen.relevance_score = score

      if score < SiteSetting.paper_surveyor_relevance_threshold.to_f
        seen.status = "irrelevant"
        seen.save! unless @dry_run
        return Result.new(seen_paper: seen, status: :irrelevant)
      end

      if @dry_run
        seen.status = "pending"
        return Result.new(seen_paper: seen, status: :would_post)
      end

      upload = PdfFetcher.new.fetch_and_store(work)
      seen.upload_id = upload&.id
      seen.save! # persist so figure rows can FK to it

      pdf_path = upload && (Discourse.store.path_for(upload) rescue nil)

      figures = annotate_figures(pdf_path, seen) if pdf_path
      full_text = extract_full_text(pdf_path) if pdf_path

      source_text =
        SiteSetting.paper_surveyor_summary_use_full_text && full_text.present? ? full_text : abstract

      summary = Summarizer.new.summarize(
        title: title,
        authors: format_authors(work),
        source_text: source_text,
        figures: figures || [],
      )

      topic = Publisher.new.publish(
        work: work,
        summary: summary,
        abstract: abstract,
        category_id: route.category_id,
      )
      seen.topic_id = topic&.id
      seen.status = topic ? "posted" : "error"
      seen.save!

      Result.new(seen_paper: seen, status: seen.status.to_sym, topic: topic)
    rescue => e
      Rails.logger.error("[paper-surveyor] pipeline error for #{work["id"]}: #{e.class}: #{e.message}")
      seen.status = "error"
      seen.error_message = "#{e.class}: #{e.message}"
      seen.save! unless @dry_run
      Result.new(seen_paper: seen, status: :error)
    end

    # OpenAlex filter hash for a specific route.
    def self.filters_for(route, from_date:, to_date: nil)
      filters = { "type" => route.work_types.join("|") }
      filters["from_publication_date"] = from_date.to_s if from_date
      filters["to_publication_date"] = to_date.to_s if to_date

      concept_ids = SiteSetting.paper_surveyor_concept_ids.to_s.split("|").reject(&:blank?)
      filters["concepts.id"] = concept_ids.join("|") if concept_ids.any?

      source_ids = SiteSetting.paper_surveyor_source_ids.to_s.split("|").reject(&:blank?)
      filters["primary_location.source.id"] = source_ids.join("|") if source_ids.any?

      filters
    end

    private

    def annotate_figures(pdf_path, seen_paper)
      return [] unless SiteSetting.paper_surveyor_extract_figures
      FigureAnnotator.new.annotate_pdf(pdf_path, seen_paper: seen_paper).select { |f| f.kind == "figure" }
    end

    def extract_full_text(pdf_path)
      PdfTextExtractor.extract(pdf_path, strip_references: SiteSetting.paper_surveyor_strip_references)
    end

    def format_authors(work)
      Array(work["authorships"]).map { |a| a.dig("author", "display_name") }.compact.join(", ")
    end
  end
end
