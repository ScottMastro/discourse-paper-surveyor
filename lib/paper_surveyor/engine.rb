# frozen_string_literal: true

module PaperSurveyor
  class Engine < ::Rails::Engine
    engine_name PaperSurveyor::PLUGIN_NAME
    isolate_namespace PaperSurveyor
    config.autoload_paths << File.join(config.root, "lib")
  end
end
