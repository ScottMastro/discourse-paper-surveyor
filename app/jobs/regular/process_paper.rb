# frozen_string_literal: true

module Jobs
  class ProcessPaper < ::Jobs::Base
    sidekiq_options queue: "low", retry: 3

    def execute(args)
      return unless SiteSetting.paper_surveyor_enabled

      work_id = args[:work_id].to_s
      route = PaperSurveyor::Route.find(args[:route])
      return if work_id.blank? || route.nil?

      short_id = work_id.sub("https://openalex.org/", "")
      return if PaperSurveyor::SeenPaper.exists?(openalex_id: short_id)

      work = PaperSurveyor::OpenAlexClient.new.fetch_work(short_id)
      PaperSurveyor::Pipeline.new.process(work, route: route)
    end
  end
end
