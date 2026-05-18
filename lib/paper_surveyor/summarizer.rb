# frozen_string_literal: true

module PaperSurveyor
  # Summarize a paper for posting. Receives the full paper text plus a
  # manifest of every figure detected (with AI-generated descriptions). The
  # model places figures inline via standard Markdown image syntax — no
  # custom placeholders, no post-processing.
  #
  # Resolution order:
  #   1. agent (preferred — admin can tune the prompt in the AI admin UI)
  #   2. raw LLM with the built-in PROMPT_TEMPLATE
  #   3. neither configured -> returns source_text unchanged
  class Summarizer
    PROMPT_TEMPLATE = <<~PROMPT
      You are summarizing a research paper for a community of %{audience}.

      Write a concise post (3-5 short paragraphs) in Discourse Markdown:
        1. One-sentence "why this matters" hook.
        2. Background and question the paper addresses.
        3. Methods — only what a reader needs to evaluate the claims.
        4. Key findings, with concrete numbers where present.
        5. Limitations or open questions the authors flag.

      Do not invent details not in the source.

      %{figures_block}

      Paper title: %{title}
      Authors: %{authors}

      Source text:
      %{source_text}
    PROMPT

    FIGURES_INSTRUCTIONS = <<~FIGS
      You may embed any of the figures below at the point in your narrative
      where they best support the surrounding paragraph. Use standard Markdown
      image syntax with the URLs given. Match figures to your narrative by
      *what they show* (per the descriptions) — not by figure number, which
      may not align with the order below. Embed any figure at most once.
      Skip figures that don't meaningfully support your text.

      For the single most informative figure, place it on its own line at the
      very top of the post (before the "why this matters" hook).

      Available figures:
    FIGS

    def initialize(
      agent_id: SiteSetting.paper_surveyor_summary_agent_id,
      model_id: SiteSetting.paper_surveyor_summary_llm_model_id
    )
      @agent_id = agent_id.to_i
      @model_id = model_id.to_i
    end

    def summarize(title:, authors:, source_text:, figures: [])
      return nil if source_text.blank?
      return source_text if @agent_id <= 0 && @model_id <= 0

      truncated = source_text.to_s[0, 80_000]

      if @agent_id > 0
        call_agent(title: title, authors: authors, source_text: truncated, figures: figures)
      else
        prompt = format(PROMPT_TEMPLATE,
                        audience: SiteSetting.paper_surveyor_field_of_interest,
                        title: title.to_s,
                        authors: authors.to_s,
                        source_text: truncated,
                        figures_block: figures_block(figures))
        call_llm(prompt)
      end
    rescue => e
      Rails.logger.warn("[paper-surveyor] summary failed: #{e.message}")
      source_text
    end

    private

    def figures_block(figures)
      return "" if figures.blank?

      lines = [FIGURES_INSTRUCTIONS]
      figures.each do |fig|
        desc = fig.description.presence || "(no description)"
        page = fig.page ? " (page #{fig.page})" : ""
        lines << "  - ![](#{fig.upload.short_url})#{page} — #{desc}"
      end
      lines.join("\n")
    end

    def ensure_discourse_ai!
      return if defined?(::DiscourseAi::Completions::Llm)
      raise "Discourse AI plugin not available"
    end

    def call_llm(prompt_text)
      ensure_discourse_ai!
      prompt = ::DiscourseAi::Completions::Prompt.new(
        messages: [{ type: :user, content: prompt_text }],
      )
      llm = ::DiscourseAi::Completions::Llm.proxy(@model_id)
      llm.generate(prompt, user: Discourse.system_user)
    end

    def call_agent(title:, authors:, source_text:, figures:)
      ensure_discourse_ai!
      agent = AiAgent.find(@agent_id)
      user_message = <<~MSG
        Paper title: #{title}
        Authors: #{authors}

        #{figures_block(figures)}

        Source text:
        #{source_text}
      MSG
      prompt = ::DiscourseAi::Completions::Prompt.new(
        agent.system_prompt,
        messages: [{ type: :user, content: user_message }],
      )
      llm = ::DiscourseAi::Completions::Llm.proxy(agent.default_llm_id)
      llm.generate(prompt, user: Discourse.system_user)
    end
  end
end
