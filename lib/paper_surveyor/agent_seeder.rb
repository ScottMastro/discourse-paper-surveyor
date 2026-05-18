# frozen_string_literal: true

module PaperSurveyor
  # Idempotently ensures two AiAgent records exist for the paper-surveyor
  # pipeline (relevance + summary) and that the corresponding site settings
  # point at them.
  #
  # `default_llm_id` is intentionally left nil — the admin must pick an LLM
  # in the AI admin UI before the agents will run. The relevance setting will
  # surface them in its dropdown immediately.
  module AgentSeeder
    RELEVANCE_NAME = "Paper Surveyor – Relevance"
    SUMMARY_NAME = "Paper Surveyor – Summary"

    RELEVANCE_PROMPT = <<~PROMPT.strip
      You are a relevance classifier for a research community.

      The community's field of interest is described in the user message
      below. Given a paper's title and abstract, score how relevant the paper
      is to that field on a scale of 0.0 to 1.0.

      Respond with ONLY a single JSON object of the form:
        {"score": <number between 0 and 1>, "reason": "<one short sentence>"}

      Do not add any commentary, code fences, or extra fields.
    PROMPT

    SUMMARY_PROMPT = <<~PROMPT.strip
      You are summarizing a research paper for a focused community of
      researchers. Write a clear, accurate post in Discourse-flavored Markdown.

      Structure:
        1. One-sentence "why this matters" hook.
        2. Background and the question the paper addresses.
        3. Methods — only what a reader needs to evaluate the claims.
        4. Key findings, with concrete numbers where present.
        5. Limitations or open questions the authors flag.

      Rules:
        - Do not invent details that are not in the source.
        - Keep paragraphs short and skimmable.
        - When figures are provided, you may embed them with `[[fig:N]]` on its
          own line at the point in the narrative where they belong. Only embed
          figures that meaningfully support the surrounding paragraph.
        - Mark the most informative single figure with `[[hero:N]]` placed at
          the very top of the post (before the "why this matters" hook).
        - Skip irrelevant figures.
    PROMPT

    module_function

    def call
      return unless ai_agent_table?

      relevance = upsert(name: RELEVANCE_NAME, prompt: RELEVANCE_PROMPT)
      summary   = upsert(name: SUMMARY_NAME,   prompt: SUMMARY_PROMPT)

      auto_wire(:paper_surveyor_relevance_agent_id, relevance&.id)
      auto_wire(:paper_surveyor_summary_agent_id, summary&.id)
    rescue => e
      Rails.logger.warn("[paper-surveyor] agent seeding skipped: #{e.class}: #{e.message}")
    end

    def ai_agent_table?
      defined?(::AiAgent) && ::AiAgent.respond_to?(:table_exists?) && ::AiAgent.table_exists?
    end

    def upsert(name:, prompt:)
      agent = ::AiAgent.find_or_initialize_by(name: name)
      created = agent.new_record?

      agent.system_prompt = prompt if created
      agent.description ||= "Auto-managed by paper-surveyor plugin."
      agent.enabled = true if created
      agent.tools ||= []
      agent.allowed_group_ids ||= [::Group::AUTO_GROUPS[:staff]] if defined?(::Group::AUTO_GROUPS)
      agent.user_id ||= ::Discourse.system_user.id if agent.respond_to?(:user_id)
      agent.save!
      agent
    end

    def auto_wire(setting, agent_id)
      return unless agent_id
      current = SiteSetting.public_send(setting).to_s
      return if current.present? && current != "0"
      SiteSetting.public_send("#{setting}=", agent_id.to_s)
    end
  end
end
