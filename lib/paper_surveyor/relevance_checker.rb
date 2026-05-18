# frozen_string_literal: true

module PaperSurveyor
  # Scores a paper's relevance to the configured field of interest.
  #
  # Resolution order:
  #   1. agent (preferred — admin can edit the prompt in the AI admin UI)
  #   2. raw LLM with our built-in prompt
  #   3. no LLM configured -> returns 1.0 (pass-through, keyword filter alone)
  class RelevanceChecker
    PROMPT_TEMPLATE = <<~PROMPT
      You are a relevance classifier for a research forum.

      Field of interest:
      %{field}

      Paper title: %{title}

      Abstract:
      %{abstract}

      On a scale of 0.0 to 1.0, how relevant is this paper to the field of interest?
      Respond with ONLY a JSON object of the form {"score": <number>, "reason": "<short reason>"}.
    PROMPT

    def initialize(
      agent_id: SiteSetting.paper_surveyor_relevance_agent_id,
      model_id: SiteSetting.paper_surveyor_relevance_llm_model_id
    )
      @agent_id = agent_id.to_i
      @model_id = model_id.to_i
    end

    def score(title:, abstract:)
      return 1.0 if @agent_id <= 0 && @model_id <= 0
      return 0.0 if abstract.blank?

      raw =
        if @agent_id > 0
          call_agent(title: title, abstract: abstract)
        else
          call_llm(build_default_prompt(title: title, abstract: abstract))
        end

      parse_score(raw)
    rescue => e
      Rails.logger.warn("[paper-surveyor] relevance check failed: #{e.class}: #{e.message}")
      0.0
    end

    private

    def build_default_prompt(title:, abstract:)
      body = format(PROMPT_TEMPLATE,
                    field: SiteSetting.paper_surveyor_field_of_interest,
                    title: title.to_s,
                    abstract: abstract.to_s[0, 4000])
      ::DiscourseAi::Completions::Prompt.new(
        messages: [{ type: :user, content: body }],
      )
    end

    def ensure_discourse_ai!
      return if defined?(::DiscourseAi::Completions::Llm)
      raise "Discourse AI plugin not available"
    end

    def call_llm(prompt)
      ensure_discourse_ai!
      llm = ::DiscourseAi::Completions::Llm.proxy(@model_id)
      llm.generate(prompt, user: Discourse.system_user)
    end

    def call_agent(title:, abstract:)
      ensure_discourse_ai!
      agent = AiAgent.find(@agent_id)
      raise "Agent #{@agent_id} has no default LLM configured" unless agent.default_llm_id

      user_message = <<~MSG
        Field of interest:
        #{SiteSetting.paper_surveyor_field_of_interest}

        Paper title: #{title}

        Abstract:
        #{abstract.to_s[0, 4000]}
      MSG
      prompt = ::DiscourseAi::Completions::Prompt.new(
        agent.system_prompt,
        messages: [{ type: :user, content: user_message }],
      )
      llm = ::DiscourseAi::Completions::Llm.proxy(agent.default_llm_id)
      llm.generate(prompt, user: Discourse.system_user)
    end

    def parse_score(raw)
      json = raw.to_s[/\{.*\}/m]
      return 0.0 unless json
      parsed = JSON.parse(json)
      parsed["score"].to_f.clamp(0.0, 1.0)
    rescue JSON::ParserError
      0.0
    end
  end
end
