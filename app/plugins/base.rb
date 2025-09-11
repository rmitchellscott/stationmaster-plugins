class Base
  # Base class for all plugins
  # Plugins should inherit from this and implement the `locals` method
  
  # OAuth Token Cache - stores access tokens in memory to avoid repeated OAuth API calls
  class OAuthTokenCache
    @@cache = {}
    @@mutex = Mutex.new
    
    def self.get_or_refresh(user_id, provider, refresh_token)
      @@mutex.synchronize do
        cache_key = "#{user_id}_#{provider}"
        cached = @@cache[cache_key]
        
        # Return cached token if still valid (with 10-minute buffer)
        if cached && cached[:expires_at] > Time.current + 10.minutes
          Rails.logger.debug "Using cached access token for #{provider} user #{user_id}"
          return cached[:access_token]
        end
        
        Rails.logger.info "Refreshing access token for #{provider} user #{user_id}"
        
        # Refresh and cache new token
        begin
          access_token = refresh_oauth_token(provider, refresh_token)
          @@cache[cache_key] = {
            access_token: access_token,
            expires_at: Time.current + 50.minutes, # Google tokens last ~1 hour, cache for 50min
            created_at: Time.current
          }
          
          # Clean up old cache entries (simple cleanup)
          cleanup_expired_tokens
          
          access_token
        rescue => e
          Rails.logger.error "Failed to refresh OAuth token for #{provider}: #{e.message}"
          nil
        end
      end
    end
    
    private
    
    def self.refresh_oauth_token(provider, refresh_token)
      case provider.downcase
      when 'google'
        refresh_google_token(refresh_token)
      when 'todoist'
        refresh_todoist_token(refresh_token)
      else
        raise "Unsupported OAuth provider: #{provider}"
      end
    end
    
    def self.refresh_google_token(refresh_token)
      require 'signet/oauth_2/client'
      
      credentials = Rails.application.credentials.plugins[:google]
      client = Signet::OAuth2::Client.new(
        client_id: credentials[:client_id],
        client_secret: credentials[:client_secret],
        token_credential_uri: 'https://accounts.google.com/o/oauth2/token',
        refresh_token: refresh_token
      )
      
      response = client.refresh!
      response['access_token']
    end
    
    def self.refresh_todoist_token(refresh_token)
      require 'oauth2'
      
      credentials = Rails.application.credentials.plugins[:todoist]
      
      # Use OAuth2 gem for cleaner implementation
      client = OAuth2::Client.new(
        credentials[:client_id],
        credentials[:client_secret],
        site: 'https://todoist.com',
        token_url: '/oauth/access_token'
      )
      
      # Create a token from the refresh token and refresh it
      token = OAuth2::AccessToken.from_hash(client, { refresh_token: refresh_token })
      new_token = token.refresh!
      
      new_token.token
    end
    
    def self.cleanup_expired_tokens
      return if @@cache.size < 50 # Only cleanup when cache gets large
      
      expired_keys = @@cache.select { |k, v| v[:expires_at] < Time.current }.keys
      expired_keys.each { |key| @@cache.delete(key) }
      
      if expired_keys.any?
        Rails.logger.debug "Cleaned up #{expired_keys.size} expired OAuth tokens from cache"
      end
    end
  end
  
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
  
  # HTTP fetch method used by plugins
  def fetch(url, headers: {}, timeout: 30, query: {}, should_retry: true)
    options = {
      headers: headers,
      timeout: timeout,
      query: query
    }
    
    retries = should_retry ? 3 : 0
    attempt = 0
    
    begin
      response = HTTParty.get(url, options)
      
      # Handle nil response
      if response.nil?
        Rails.logger.error "API call to #{url} returned nil response"
        return create_error_response("API returned nil response")
      end
      
      # Log complete API response for debugging
      Rails.logger.info "=== API Response for #{url} ==="
      Rails.logger.info "Response code: #{response.code rescue 'unknown'}"
      Rails.logger.info "Response headers: #{response.headers.inspect rescue 'unknown'}"
      Rails.logger.info "Response body: #{response.body.inspect rescue 'unknown'}"
      Rails.logger.info "Parsed response: #{response.parsed_response.inspect rescue 'unknown'}"
      Rails.logger.info "=== End API Response ==="
      
      response
      
    rescue => e
      attempt += 1
      if attempt <= retries
        Rails.logger.warn "HTTP request failed (attempt #{attempt}/#{retries + 1}): #{e.message}"
        sleep(attempt * 0.5) # exponential backoff
        retry
      else
        Rails.logger.error "Failed to fetch from #{url} after #{attempt} attempts: #{e.message}"
        return create_error_response("HTTP request failed: #{e.message}")
      end
    end
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
  
  # Plugin metadata object providing access to form fields
  def plugin
    @plugin ||= PluginProxy.new(self.class.name.demodulize.underscore)
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
  
  # Helper method to convert comma-separated string to array with optional limit
  def string_to_array(string, limit: nil)
    return [] if string.nil? || string.empty?
    
    array = string.split(',').map(&:strip).reject(&:empty?)
    limit ? array.first(limit) : array
  end
  
  # Helper method to convert line-separated string to array  
  def line_separated_string_to_array(string)
    return [] if string.nil? || string.empty?
    
    string.split(/[\r\n]+/).map(&:strip).reject(&:empty?)
  end

  private
  
  # Create a consistent error response structure for failed API calls
  def create_error_response(error_message)
    # Return a mock HTTParty response-like object that Stock Price plugin can handle
    OpenStruct.new(
      code: 500,
      body: nil,
      parsed_response: { 's' => 'error', 'errmsg' => error_message },
      '[]' => ->(key) { parsed_response[key] }
    )
  end
  
  public
  
  # Override settings to provide OAuth token injection
  def settings
    @wrapped_settings ||= wrap_oauth_settings(@settings)
  end
  
  private
  
  # Wraps settings to inject OAuth tokens transparently
  def wrap_oauth_settings(original_settings)
    # Start with original settings
    wrapped = original_settings.dup
    
    # Only inject OAuth tokens if we have them from Go
    oauth_tokens = @trmnl_data&.dig('oauth_tokens')
    user_data = @trmnl_data&.dig('user')
    
    return wrapped unless oauth_tokens && user_data
    
    user_id = user_data['id']
    return wrapped unless user_id
    
    # Inject Google Analytics tokens
    if oauth_tokens['google']&.dig('refresh_token')
      refresh_token = oauth_tokens['google']['refresh_token']
      access_token = OAuthTokenCache.get_or_refresh(user_id, 'google', refresh_token)
      
      # Always inject refresh token, access token is optional (plugin can refresh if needed)
      wrapped['google_analytics'] = {
        'refresh_token' => refresh_token
      }
      wrapped['google_analytics']['access_token'] = access_token if access_token
    end
    
    # Inject YouTube Analytics tokens (uses same Google credentials)
    if oauth_tokens['google']&.dig('refresh_token')
      refresh_token = oauth_tokens['google']['refresh_token']
      access_token = OAuthTokenCache.get_or_refresh(user_id, 'google', refresh_token)
      
      # Always inject refresh token, access token is optional
      wrapped['youtube_analytics'] = {
        'refresh_token' => refresh_token
      }
      wrapped['youtube_analytics']['access_token'] = access_token if access_token
    end
    
    # Inject Google Calendar tokens (uses same Google credentials)
    if oauth_tokens['google']&.dig('refresh_token')
      refresh_token = oauth_tokens['google']['refresh_token']
      access_token = OAuthTokenCache.get_or_refresh(user_id, 'google', refresh_token)
      
      # Always inject refresh token, access token is optional
      wrapped['google_calendar'] = {
        'refresh_token' => refresh_token
      }
      wrapped['google_calendar']['access_token'] = access_token if access_token
    end
    
    # Inject Todoist tokens
    if oauth_tokens['todoist']&.dig('refresh_token')
      refresh_token = oauth_tokens['todoist']['refresh_token']
      access_token = OAuthTokenCache.get_or_refresh(user_id, 'todoist', refresh_token)
      
      # Always inject refresh token, access token is optional
      wrapped['todoist'] = {
        'refresh_token' => refresh_token
      }
      wrapped['todoist']['access_token'] = access_token if access_token
    end
    
    wrapped
  end
  
  public
  
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
  
  # Proxy class to provide plugin metadata functionality
  class PluginProxy
    def initialize(plugin_name)
      @plugin_name = plugin_name
    end
    
    # Get plugin form fields from form_fields.yaml
    def account_fields
      @account_fields ||= begin
        form_fields_path = Rails.root.join('app', 'plugins', @plugin_name, 'form_fields.yaml')
        
        if File.exist?(form_fields_path)
          fields = YAML.load_file(form_fields_path) || []
          
          # Transform select field options to extract just the values
          fields.each do |field|
            if field['field_type'] == 'select' && field['options'].is_a?(Array)
              field['options'] = field['options'].map do |option|
                if option.is_a?(Hash)
                  # Extract just the values from hash options like {"US Dollar (USD)" => "USD"}
                  option.values.first
                else
                  option
                end
              end
            end
          end
          
          fields
        else
          Rails.logger.warn "No form_fields.yaml found for plugin: #{@plugin_name}"
          []
        end
      rescue => e
        Rails.logger.error "Error loading form fields for #{@plugin_name}: #{e.message}"
        []
      end
    end
  end
end