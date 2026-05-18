# frozen_string_literal: true

module PaperSurveyor
  # A Route binds a set of OpenAlex work types to a Discourse category.
  # Currently two routes are exposed via site settings (preprints + articles)
  # but the model is extensible — add a new entry in `Route.configured` and
  # the rest of the pipeline picks it up.
  Route = Struct.new(:name, :work_types, :category_id, keyword_init: true) do
    def enabled?
      category_id.to_i > 0 && work_types.any?
    end

    def self.configured
      [
        new(
          name: "preprint",
          work_types: SiteSetting.paper_surveyor_preprint_work_types.to_s.split("|").reject(&:blank?),
          category_id: SiteSetting.paper_surveyor_preprint_category_id.to_i,
        ),
        new(
          name: "article",
          work_types: SiteSetting.paper_surveyor_article_work_types.to_s.split("|").reject(&:blank?),
          category_id: SiteSetting.paper_surveyor_article_category_id.to_i,
        ),
      ].select(&:enabled?)
    end

    def self.find(name)
      configured.find { |r| r.name == name.to_s }
    end
  end
end
