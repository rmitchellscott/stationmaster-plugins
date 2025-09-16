# OAuth Credentials Initializer
# 
# This initializer dynamically adds plugins credentials from environment variables
# to enable existing OAuth plugins to access client credentials without code modification.

# Build the plugins hash from environment variables
oauth_plugins = {}

# Google OAuth credentials
if ENV['GOOGLE_CLIENT_ID'].present? && ENV['GOOGLE_CLIENT_SECRET'].present?
  oauth_plugins[:google] = {
    client_id: ENV['GOOGLE_CLIENT_ID'],
    client_secret: ENV['GOOGLE_CLIENT_SECRET']
  }
end

# Todoist OAuth credentials  
if ENV['TODOIST_CLIENT_ID'].present? && ENV['TODOIST_CLIENT_SECRET'].present?
  oauth_plugins[:todoist] = {
    client_id: ENV['TODOIST_CLIENT_ID'],
    client_secret: ENV['TODOIST_CLIENT_SECRET']
  }
end

# API Key credentials for plugins that require them

# GitHub commit graph token
if ENV['GITHUB_API_TOKEN'].present?
  oauth_plugins[:github_commit_graph_token] = ENV['GITHUB_API_TOKEN']
end

# Currency API key
if ENV['CURRENCY_API_KEY'].present?
  oauth_plugins[:currency_api] = ENV['CURRENCY_API_KEY']
end

# MarketData API token
if ENV['MARKETDATA_API_TOKEN'].present?
  oauth_plugins[:marketdata_app] = ENV['MARKETDATA_API_TOKEN']
end

# Monkey patch Rails credentials to add plugins support
# This approach preserves the existing Rails credentials while adding our plugins data
# Use after_initialize to ensure this runs after encrypted credentials are loaded
Rails.application.config.after_initialize do
  # First remove any existing plugins method from encrypted credentials
  Rails.application.credentials.singleton_class.send(:remove_method, :plugins) rescue nil

  Rails.application.credentials.define_singleton_method(:plugins) do
    # Return the plugins hash with method access support
    @plugins_accessor ||= begin
      plugins_hash = oauth_plugins.dup
      
      # Add method access support
      plugins_hash.define_singleton_method(:method_missing) do |method_name, *args, &block|
        key = method_name.to_sym
        if self.key?(key)
          self[key]
        else
          super(method_name, *args, &block)
        end
      end
      
      plugins_hash.define_singleton_method(:respond_to_missing?) do |method_name, include_private = false|
        self.key?(method_name.to_sym) || super(method_name, include_private)
      end
      
      plugins_hash
    end
  end
end

# Add base_url method for OAuth redirects
Rails.application.credentials.define_singleton_method(:base_url) do
  ENV['RAILS_BASE_URL'] || 'http://localhost:3000'
end

# Log available OAuth providers at startup
oauth_provider_keys = oauth_plugins.keys
Rails.logger.info "OAuth providers configured: #{oauth_provider_keys.join(', ')}" if oauth_provider_keys.any?