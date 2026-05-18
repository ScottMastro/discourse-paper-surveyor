# frozen_string_literal: true

module PaperSurveyor
  # Pipeline step: extract every image from the PDF, upload each via
  # UploadCreator, and ask a vision-capable LLM to classify and describe it.
  # Results are persisted as PaperSurveyor::Figure rows so they can be reused
  # by the summarizer (and inspected from the admin UI).
  class FigureAnnotator
    PROMPT_SYSTEM = <<~PROMPT.strip
      You are classifying images extracted from an academic PDF.

      For each image, decide what it is and describe it in a single dense
      sentence (max 30 words) that captures *what is shown* — the kind of plot,
      the variables on the axes if visible, the entities compared, the
      qualitative pattern. Do not speculate about meaning beyond what is in
      the image.

      Respond ONLY with a single JSON object:
        {"kind": "figure" | "table" | "boilerplate" | "other",
         "description": "<one sentence>"}

      Use "boilerplate" for journal logos, page headers, decorative banners,
      QR codes, watermarks. Use "table" for screenshots/renders of tabular data.
      Use "other" for anything that doesn't fit. Use "figure" for charts,
      plots, diagrams, micrographs, photographs of specimens, and the like.
    PROMPT

    def initialize(model_id: SiteSetting.paper_surveyor_figure_llm_model_id)
      @model_id = model_id.to_i
    end

    def annotate_pdf(pdf_path, seen_paper:)
      return [] unless pdf_path && File.exist?(pdf_path)

      images = PdfImageExtractor.extract(pdf_path)
      return [] if images.empty?

      images.map do |img|
        upload = upload_image(img)
        next nil unless upload

        annotation = annotate_one(upload) if @model_id > 0
        annotation ||= { kind: "unknown", description: nil }

        figure = PaperSurveyor::Figure.create!(
          seen_paper_id: seen_paper.id,
          upload_id: upload.id,
          sequence_index: img.sequence_index,
          page: img.page,
          kind: annotation[:kind],
          description: annotation[:description],
          annotated_with: @model_id > 0 ? "llm:#{@model_id}" : nil,
        )
        File.unlink(img.path) rescue nil
        figure
      end.compact
    end

    private

    def upload_image(img)
      file = File.open(img.path, "rb")
      filename = "fig-#{img.sequence_index.to_s.rjust(3, "0")}.png"
      upload = UploadCreator
        .new(file, filename, type: "paper_surveyor_figure")
        .create_for(Discourse.system_user.id)
      file.close
      upload&.persisted? ? upload : nil
    rescue => e
      Rails.logger.warn("[paper-surveyor] figure upload failed: #{e.message}")
      nil
    end

    def annotate_one(upload)
      raw = call_vision_llm(upload)
      parse_response(raw)
    rescue => e
      Rails.logger.warn("[paper-surveyor] vision annotation failed for upload #{upload.id}: #{e.message}")
      nil
    end

    def call_vision_llm(upload)
      raise "Discourse AI not available" unless defined?(::DiscourseAi::Completions::Llm)

      prompt = ::DiscourseAi::Completions::Prompt.new(
        PROMPT_SYSTEM,
        messages: [
          {
            type: :user,
            content: [
              "Classify and describe the attached image.",
              { upload_id: upload.id },
            ],
          },
        ],
      )

      llm = ::DiscourseAi::Completions::Llm.proxy(@model_id)
      llm.generate(prompt, user: Discourse.system_user)
    end

    def parse_response(raw)
      json = raw.to_s[/\{.*\}/m]
      return nil unless json
      parsed = JSON.parse(json)
      kind = parsed["kind"].to_s.downcase
      kind = "unknown" unless PaperSurveyor::Figure::KINDS.include?(kind)
      { kind: kind, description: parsed["description"].to_s.strip.presence }
    rescue JSON::ParserError
      nil
    end
  end
end
