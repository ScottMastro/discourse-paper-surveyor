# frozen_string_literal: true

# name: paper-surveyor
# about: Polls OpenAlex for new preprints and articles, filters them by relevance with Discourse AI, and posts summaries.
# meta_topic_id: TODO
# version: 0.1.0
# authors: pangytalk
# url: https://github.com/pangytalk/paper-surveyor
# required_version: 2.7.0

enabled_site_setting :paper_surveyor_enabled

register_asset "stylesheets/paper-surveyor.scss"

module ::PaperSurveyor
  PLUGIN_NAME = "paper-surveyor"
end

require_relative "lib/paper_surveyor/engine"

after_initialize do
  require_relative "lib/paper_surveyor/open_alex_client"
  require_relative "lib/paper_surveyor/abstract_reconstructor"
  require_relative "lib/paper_surveyor/text_cleaner"
  require_relative "lib/paper_surveyor/relevance_checker"
  require_relative "lib/paper_surveyor/summarizer"
  require_relative "lib/paper_surveyor/pdf_fetcher"
  require_relative "lib/paper_surveyor/pdf_text_extractor"
  require_relative "lib/paper_surveyor/pdf_image_extractor"
  require_relative "lib/paper_surveyor/figure_annotator"
  require_relative "lib/paper_surveyor/route"
  require_relative "lib/paper_surveyor/citation_formatter"
  require_relative "lib/paper_surveyor/publisher"
  require_relative "lib/paper_surveyor/pipeline"
  require_relative "lib/paper_surveyor/agent_seeder"

  require_relative "app/models/paper_surveyor/seen_paper"
  require_relative "app/models/paper_surveyor/backfill_run"
  require_relative "app/models/paper_surveyor/figure"

  require_relative "app/jobs/scheduled/poll_papers"
  require_relative "app/jobs/regular/process_paper"
  require_relative "app/jobs/regular/run_backfill"

  require_relative "app/controllers/paper_surveyor/admin_controller"
  require_relative "app/serializers/paper_surveyor/paper_serializer"

  Discourse::Application.routes.append do
    scope "/admin/plugins/paper-surveyor", constraints: AdminConstraint.new do
      get  "/papers" => "paper_surveyor/admin#papers"
      post "/backfill" => "paper_surveyor/admin#start_backfill"
      get  "/backfill/:id" => "paper_surveyor/admin#backfill_status"
      post "/poll_now" => "paper_surveyor/admin#poll_now"
    end
  end

  # Seed AI agents once Rails is fully booted (DB + Discourse AI loaded).
  Rails.application.config.after_initialize do
    PaperSurveyor::AgentSeeder.call
  end
end

add_admin_route "paper_surveyor.title", "paper-surveyor", use_new_show_route: true
