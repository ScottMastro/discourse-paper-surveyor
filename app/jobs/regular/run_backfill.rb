# frozen_string_literal: true

module Jobs
  # Walks OpenAlex over a date range for every configured Route and pushes
  # each match through the standard pipeline. Resumable via the row's cursor.
  class RunBackfill < ::Jobs::Base
    sidekiq_options queue: "low", retry: false

    def execute(args)
      run = PaperSurveyor::BackfillRun.find_by(id: args[:run_id])
      return unless run
      run.update!(status: "running")

      routes = PaperSurveyor::Route.configured
      if routes.empty?
        run.update!(status: "failed", error_message: "No routes configured")
        return
      end

      client = PaperSurveyor::OpenAlexClient.new
      pipeline = PaperSurveyor::Pipeline.new(dry_run: run.dry_run)
      search = run.search_query.presence || SiteSetting.paper_surveyor_search_query.presence

      routes.each do |route|
        walk_route(run: run, route: route, client: client, pipeline: pipeline, search: search)
        return if run.cancelled?
      end

      run.update!(status: "completed")
    rescue => e
      Rails.logger.error("[paper-surveyor] backfill #{args[:run_id]} failed: #{e.class}: #{e.message}")
      run&.update(status: "failed", error_message: "#{e.class}: #{e.message}")
    end

    private

    def walk_route(run:, route:, client:, pipeline:, search:)
      filters = PaperSurveyor::Pipeline.filters_for(route, from_date: run.from_date, to_date: run.to_date)
      cursor = "*"

      loop do
        return if run.cancelled?

        page = client.fetch_page(filters: filters, search: search, cursor: cursor)
        results = page["results"] || []
        break if results.empty?

        results.each do |work|
          run.increment!(:scanned_count)
          result = pipeline.process(work, route: route)
          case result.status
          when :would_post, :posted
            run.increment!(:posted_count)
            run.increment!(:relevant_count)
            run.increment!(:passed_filter_count)
          when :irrelevant
            run.increment!(:passed_filter_count)
          when :error
            run.increment!(:error_count)
          end
        end

        cursor = page.dig("meta", "next_cursor")
        run.update!(cursor: cursor)
        break if cursor.blank?
      end
    end
  end
end
