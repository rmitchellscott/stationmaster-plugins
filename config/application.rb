require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
# require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module StationmasterPlugins
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
    
    # Load TRMNL internationalization locales
    config.after_initialize do
      require 'trmnl/i18n'
      TRMNL::I18n.load_locales
      
      # Set base_url from environment variable for image serving
      if ENV['RAILS_BASE_URL']
        Rails.application.credentials.define_singleton_method(:base_url) { ENV['RAILS_BASE_URL'] }
      end
      
      # Configure GitHub API token from environment variable
      if ENV['GITHUB_API_TOKEN']
        # Create nested credentials structure for plugins.github_commit_graph_token
        plugins_credentials = Struct.new(:github_commit_graph_token).new(ENV['GITHUB_API_TOKEN'])
        Rails.application.credentials.define_singleton_method(:plugins) { plugins_credentials }
      end
    end
  end
end
