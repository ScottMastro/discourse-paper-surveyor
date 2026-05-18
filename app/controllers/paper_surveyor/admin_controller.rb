# frozen_string_literal: true

module PaperSurveyor
  class AdminController < ::Admin::AdminController
    requires_plugin PaperSurveyor::PLUGIN_NAME

    PER_PAGE = 25

    def index
      # serves the admin SPA shell; the Ember app renders the page
      render json: { ok: true }
    end

    def papers
      scope = SeenPaper.all
      scope = scope.where(status: params[:status]) if params[:status].present? && params[:status] != "all"
      if params[:route].present? && params[:route] != "all"
        scope = scope.where("metadata->>'route' = ?", params[:route])
      end
      if params[:search].present?
        q = "%#{params[:search].downcase}%"
        scope = scope.where(
          "LOWER(openalex_id) LIKE :q OR LOWER(doi) LIKE :q OR LOWER(metadata->>'title') LIKE :q",
          q: q,
        )
      end

      total = scope.count
      page = [params[:page].to_i, 1].max
      papers = scope.order(created_at: :desc).limit(PER_PAGE).offset((page - 1) * PER_PAGE)

      counts = SeenPaper.group(:status).count
      counts["all"] = SeenPaper.count

      render json: {
        papers: ActiveModel::ArraySerializer.new(papers, each_serializer: PaperSerializer).as_json,
        meta: {
          total: total,
          page: page,
          per_page: PER_PAGE,
          total_pages: (total.to_f / PER_PAGE).ceil,
          status_counts: counts,
        },
      }
    end

    def start_backfill
      from_date = Date.parse(params.require(:from_date))
      to_date = Date.parse(params.require(:to_date))
      run = BackfillRun.create!(
        from_date: from_date,
        to_date: to_date,
        search_query: params[:search_query],
        dry_run: ActiveModel::Type::Boolean.new.cast(params[:dry_run]),
        triggered_by_user_id: current_user.id,
      )
      Jobs.enqueue(:run_backfill, run_id: run.id)
      render json: { id: run.id, status: run.status }
    end

    def backfill_status
      run = BackfillRun.find_by(id: params[:id])
      return render_json_error(I18n.t("paper_surveyor.backfill.not_found"), status: 404) unless run
      render json: run.as_json
    end

    def poll_now
      Jobs.enqueue(:poll_papers)
      render json: { ok: true }
    end
  end
end
