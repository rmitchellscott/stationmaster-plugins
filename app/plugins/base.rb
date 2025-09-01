class Base
  # Base class for all plugins
  # Plugins should inherit from this and implement the `locals` method
  
  def initialize(settings = {}, trmnl_data = {})
    @settings = settings || {}
    @trmnl_data = trmnl_data || {}
  end
  
  # Main method that should be implemented by plugins
  # Returns a hash of data to be used in template rendering
  def locals
    raise NotImplementedError, "#{self.class} must implement #locals method"
  end
  
  # Helper method for making HTTP requests
  def fetch_data(url, headers = {})
    HTTParty.get(url, headers: headers)
  rescue => e
    Rails.logger.error "Failed to fetch data from #{url}: #{e.message}"
    nil
  end
  
  # Helper method for getting current time
  def current_time
    Time.current
  end
  
  # Helper method for formatting time
  def format_time(time, format = "%I:%M %p")
    time.strftime(format)
  end
  
  # Helper method for accessing settings
  def setting(key, default = nil)
    @settings[key.to_s] || @settings[key.to_sym] || default
  end
  
  # User object providing timezone and datetime capabilities
  def user
    @user ||= UserProxy.new(@trmnl_data['user'] || {})
  end
  
  # Plugin settings object providing metadata and created_at date
  def plugin_settings
    @plugin_settings ||= PluginSettingsProxy.new(@trmnl_data['plugin_settings'] || {})
  end
  
  # Helper method for accessing user locale
  def locale
    user.locale
  end
  
  # Helper method for Rails translations
  def t(key, **options)
    I18n.t(key, **options)
  end
  
  # Helper method for Rails localization
  def l(object, **options)
    I18n.l(object, **options)
  end
  
  # Ensure Rails compatibility for templates
  def self.ensure_rails_compatibility!
    return if defined?(Rails) && Rails.respond_to?(:application)
    
    # Create minimal Rails mock for template compatibility
    rails_mock = Struct.new(:application) do
      def credentials
        @credentials ||= Struct.new(:base_url, :plugins) do
          def base_url
            ENV['RAILS_BASE_URL'] || 'http://localhost:3000'
          end
          
          def plugins
            {}
          end
        end.new
      end
    end
    
    app_mock = Struct.new(:credentials) do
      def credentials
        @credentials ||= Struct.new(:base_url, :plugins) do
          def base_url
            ENV['RAILS_BASE_URL'] || 'http://localhost:3000'
          end
          
          def plugins
            {}
          end
        end.new
      end
    end
    
    Object.const_set(:Rails, rails_mock.new(app_mock.new)) unless defined?(Rails)
  end
  
  private
  
  attr_reader :settings
  
  # Proxy class to provide user datetime and timezone functionality
  class UserProxy
    def initialize(user_data)
      @user_data = user_data
    end
    
    # Get current datetime in user's timezone
    def datetime_now
      timezone = @user_data['time_zone_iana'] || 'UTC'
      Time.current.in_time_zone(timezone)
    end
    
    # Get user's timezone
    def tz
      @user_data['time_zone_iana'] || 'UTC'
    end
    
    # Get user's locale
    def locale
      @user_data['locale'] || 'en'
    end
  end
  
  # Proxy class to provide plugin settings functionality
  class PluginSettingsProxy
    def initialize(plugin_settings_data)
      @plugin_settings_data = plugin_settings_data
    end
    
    # Get plugin instance creation date
    def created_at
      created_at_str = @plugin_settings_data['created_at']
      return Time.current unless created_at_str
      
      Time.parse(created_at_str)
    rescue ArgumentError
      Time.current
    end
    
    # Get plugin instance ID
    def id
      @plugin_settings_data['id']
    end
    
    # Placeholder methods for OAuth plugins (to be implemented later)
    def encrypted_settings
      {}
    end
    
    def settings
      {}
    end
    
    def update(attributes)
      # No-op for now - OAuth plugins will need this later
      Rails.logger.warn "PluginSettingsProxy#update called but not implemented for external plugins"
    end
    
    def refresh_in_24hr
      # No-op for now - caching strategy for OAuth plugins
      Rails.logger.warn "PluginSettingsProxy#refresh_in_24hr called but not implemented for external plugins"
    end
  end
end