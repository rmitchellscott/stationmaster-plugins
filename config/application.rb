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
      
      # Configure API tokens from environment variables with independent fallbacks
      if ENV['GITHUB_API_TOKEN'] || ENV['MARKETDATA_API_TOKEN'] || ENV['CURRENCY_API_KEY']
        # Create a simple Struct with dynamic field population that falls back to encrypted credentials
        plugins_struct = Struct.new(:github_commit_graph_token, :marketdata_app, :currency_api, :google, :full_calendar) do
          # Override field accessors to support environment variable fallbacks
          def github_commit_graph_token
            ENV['GITHUB_API_TOKEN'] || (original_plugins&.github_commit_graph_token rescue nil)
          end
          
          def marketdata_app
            token = ENV['MARKETDATA_API_TOKEN'] || (original_plugins&.[](:marketdata_app) rescue nil)
            Rails.logger.debug "marketdata_app token: #{token ? 'present' : 'nil'} (env: #{ENV['MARKETDATA_API_TOKEN'] ? 'present' : 'nil'})"
            token
          end
          
          def currency_api  
            key = ENV['CURRENCY_API_KEY'] || (original_plugins&.currency_api rescue nil)
            Rails.logger.debug "currency_api key: #{key ? 'present' : 'nil'} (env: #{ENV['CURRENCY_API_KEY'] ? 'present' : 'nil'})"
            key
          end
          
          def google
            # Return original google credentials (no env var override for nested OAuth)
            original_plugins&.[](:google) rescue nil
          end
          
          def full_calendar
            # Return original full_calendar credentials (no env var override for nested)
            original_plugins&.full_calendar rescue nil
          end
          
          # Support bracket notation access
          def [](key)
            case key.to_s
            when 'github_commit_graph_token'
              github_commit_graph_token
            when 'marketdata_app'
              marketdata_app
            when 'currency_api'
              currency_api
            when 'google'
              google
            when 'full_calendar'
              full_calendar
            else
              original_plugins&.[](key) rescue nil
            end
          end
          
          private
          
          def original_plugins
            @original_plugins ||= begin
              # Capture original plugins credentials at runtime to avoid timing issues
              Rails.application.credentials.instance_variable_get(:@config)&.[](:plugins)
            rescue
              nil
            end
          end
        end.new
        
        Rails.application.credentials.define_singleton_method(:plugins) { plugins_struct }
      end
    end
  end
end
