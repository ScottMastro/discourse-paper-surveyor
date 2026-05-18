# frozen_string_literal: true

module Jobs
  class PollPapers < ::Jobs::Scheduled
    every 1.hour

    def execute(_args)
      return unless SiteSetting.paper_surveyor_enabled

      routes = PaperSurveyor::Route.configured
      return if routes.empty?

      from = SiteSetting.paper_surveyor_poll_lookback_days.to_i.days.ago.to_date
      client = PaperSurveyor::OpenAlexClient.new
      search = SiteSetting.paper_surveyor_search_query.presence

      routes.each do |route|
        filters = PaperSurveyor::Pipeline.filters_for(route, from_date: from)
        client.each_work(filters: filters, search: search) do |work|
          Jobs.enqueue(:process_paper, work_id: work["id"], route: route.name)
        end
      end
    end
  end
end
