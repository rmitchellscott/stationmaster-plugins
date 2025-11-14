class Api::PluginOptionsController < Api::BaseController
  # Simple in-memory cache for plugin options (expires after 5 minutes)
  @@options_cache = {}
  @@cache_timestamps = {}
  CACHE_DURATION = 5.minutes
  
  def fetch
    plugin_identifier = params[:plugin_identifier]
    field_name = params[:field_name]

    Rails.logger.info "Fetching dynamic options for #{plugin_identifier}.#{field_name}"

    begin
      # Get OAuth tokens from request
      oauth_tokens = params[:oauth_tokens] || {}
      user_data = params[:user] || {}
      user_id = user_data['id'] || 'anonymous'

      # Use the plugin identifier directly
      actual_plugin_identifier = plugin_identifier

      # Check cache first (use actual identifier for cache key)
      cache_key = "#{user_id}:#{actual_plugin_identifier}:#{field_name}"
      cached_options = get_cached_options(cache_key)

      if cached_options
        Rails.logger.info "Returning cached options for #{cache_key}"
        return render_success({
          options: cached_options,
          field_name: field_name,
          plugin: actual_plugin_identifier,
          cached_at: @@cache_timestamps[cache_key].iso8601,
          from_cache: true
        })
      end

      # Load the plugin class using actual identifier
      plugin_class = load_plugin_class(actual_plugin_identifier)
      
      unless plugin_class
        return render_error("Plugin not found: #{actual_plugin_identifier}", status: :not_found)
      end

      # Check if the plugin has the requested method
      method_name = field_name.to_sym
      unless plugin_class.respond_to?(method_name)
        return render_error("Plugin does not support fetching #{field_name}", status: :unprocessable_entity)
      end

      # Get options based on the plugin and field
      Rails.logger.info "Fetching options for #{actual_plugin_identifier}.#{field_name}"
      Rails.logger.info "Plugin class: #{plugin_class.name}"
      Rails.logger.info "Method name: #{method_name}"
      Rails.logger.info "OAuth tokens present: #{oauth_tokens.present?}"

      options = fetch_plugin_options(plugin_class, method_name, actual_plugin_identifier, oauth_tokens, user_data)
      
      Rails.logger.info "Options returned: #{options.inspect}"
      
      if options
        # Cache the successful result
        set_cached_options(cache_key, options)
        
        render_success({
          options: options,
          field_name: field_name,
          plugin: actual_plugin_identifier,
          cached_at: Time.current.iso8601,
          from_cache: false
        })
      else
        render_error("Failed to fetch options", status: :unprocessable_entity)
      end
      
    rescue => e
      Rails.logger.error "Failed to fetch plugin options: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render_error(
        "Failed to fetch options: #{e.message}",
        status: :internal_server_error,
        details: { error_class: e.class.name }
      )
    end
  end
  
  private


  def load_plugin_class(plugin_identifier)
    plugin_file = Rails.root.join('app', 'plugins', plugin_identifier, "#{plugin_identifier}.rb")

    unless File.exist?(plugin_file)
      return nil
    end

    # Load base class if needed
    base_file = Rails.root.join('app', 'plugins', 'base.rb')
    if File.exist?(base_file)
      require base_file
    end

    # Load any helper files first
    helpers_dir = Rails.root.join('app', 'plugins', plugin_identifier, 'helpers')
    if Dir.exist?(helpers_dir)
      Dir.glob(File.join(helpers_dir, '**', '*.rb')).sort.each do |helper_file|
        require helper_file
      end
    end

    # Load the plugin file
    require plugin_file

    # Find the plugin class
    class_name = plugin_identifier.camelize

    # Try to get the class from Plugins module
    if defined?(Plugins) && Plugins.const_defined?(class_name)
      return Plugins.const_get(class_name)
    end

    # Try global namespace
    if Object.const_defined?(class_name)
      return Object.const_get(class_name)
    end

    nil
  rescue => e
    Rails.logger.error "Failed to load plugin class for #{plugin_identifier}: #{e.message}"
    nil
  end
  
  def fetch_plugin_options(plugin_class, method_name, plugin_identifier, oauth_tokens, user_data)
    case plugin_identifier
    when 'calendar', 'google_calendar'
      fetch_google_calendar_options(plugin_class, method_name, oauth_tokens, user_data)
    when 'todoist'
      fetch_todoist_options(plugin_class, method_name, oauth_tokens, user_data)
    else
      # Generic OAuth plugin handling
      fetch_generic_oauth_options(plugin_class, method_name, oauth_tokens, user_data, plugin_identifier)
    end
  end
  
  def fetch_google_calendar_options(plugin_class, method_name, oauth_tokens, user_data)
    # Google Calendar uses 'google' as the OAuth provider key
    Rails.logger.info "Google Calendar options fetch - OAuth tokens: #{oauth_tokens.keys.inspect}"
    google_tokens = oauth_tokens['google'] || {}
    Rails.logger.info "Google tokens found: #{google_tokens.keys.inspect}"
    
    if google_tokens['refresh_token'].blank?
      Rails.logger.warn "No Google refresh token available"
      return nil
    end
    
    # Get or refresh access token
    user_id = user_data['id'] || 'temp_user'
    access_token = Base::OAuthTokenCache.get_or_refresh(user_id, 'google', google_tokens['refresh_token'])
    
    unless access_token
      Rails.logger.error "Failed to get Google access token"
      return nil
    end
    
    # Build credentials hash in the format the plugin expects
    credentials = {
      'google_calendar' => {
        'access_token' => access_token,
        'refresh_token' => google_tokens['refresh_token']
      }
    }
    
    # Call the plugin's class method
    Rails.logger.info "Calling method: #{method_name}"
    case method_name
    when :list_calendar
      Rails.logger.info "Fetching calendar list"
      # Returns array of {name => id} hashes
      calendars = plugin_class.list_calendar(credentials)
      Rails.logger.info "Calendars returned: #{calendars.inspect}"
      # Convert to frontend-friendly format
      result = calendars.map do |calendar_hash|
        calendar_hash.map { |name, id| { label: name, value: id } }
      end.flatten
      Rails.logger.info "Formatted result: #{result.inspect}"
      result
    else
      Rails.logger.warn "Unknown method: #{method_name}"
      nil
    end
  rescue => e
    Rails.logger.error "Failed to fetch Google Calendar options: #{e.message}"
    nil
  end
  
  def fetch_todoist_options(plugin_class, method_name, oauth_tokens, user_data)
    todoist_tokens = oauth_tokens['todoist'] || {}

    Rails.logger.info "Todoist tokens received: keys=#{todoist_tokens.keys.inspect}, has_refresh=#{todoist_tokens['refresh_token'].present?}, has_access=#{todoist_tokens['access_token'].present?}"

    # Todoist uses long-lived access tokens
    access_token = todoist_tokens['access_token'] || todoist_tokens['refresh_token']

    if access_token.blank?
      Rails.logger.warn "No Todoist access token available (tokens: #{todoist_tokens.inspect})"
      return nil
    end

    unless access_token
      Rails.logger.error "Failed to get Todoist access token"
      return nil
    end
    
    # Call the plugin's class method
    case method_name
    when :projects
      # Returns array of {name => id} hashes
      projects = plugin_class.projects(access_token)
      # Convert to frontend-friendly format
      projects.map do |project_hash|
        project_hash.map { |name, id| { label: name, value: id.to_s } }
      end.flatten
    when :labels
      # Returns array of {name => name} hashes
      labels = plugin_class.labels(access_token)
      # Convert to frontend-friendly format
      labels.map do |label_hash|
        label_hash.map { |name, _| { label: name, value: name } }
      end.flatten
    else
      nil
    end
  rescue => e
    Rails.logger.error "Failed to fetch Todoist options: #{e.message}"
    nil
  end
  
  def fetch_generic_oauth_options(plugin_class, method_name, oauth_tokens, user_data, plugin_identifier)
    # Generic handling for other OAuth plugins
    plugin_tokens = oauth_tokens[plugin_identifier] || {}
    
    if plugin_tokens['refresh_token'].blank?
      Rails.logger.warn "No refresh token available for #{plugin_identifier}"
      return nil
    end
    
    # Get or refresh access token
    user_id = user_data['id'] || 'temp_user'
    access_token = Base::OAuthTokenCache.get_or_refresh(user_id, plugin_identifier, plugin_tokens['refresh_token'])
    
    unless access_token
      Rails.logger.error "Failed to get access token for #{plugin_identifier}"
      return nil
    end
    
    # Try to call the method with access token
    result = plugin_class.public_send(method_name, access_token)
    
    # Convert result to options format
    if result.is_a?(Array)
      result.map do |item|
        if item.is_a?(Hash)
          # Assume first key-value pair is label-value
          label, value = item.first
          { label: label.to_s, value: value.to_s }
        else
          { label: item.to_s, value: item.to_s }
        end
      end
    else
      nil
    end
  rescue => e
    Rails.logger.error "Failed to fetch options for #{plugin_identifier}: #{e.message}"
    nil
  end
  
  def get_cached_options(cache_key)
    return nil unless @@cache_timestamps[cache_key]
    
    # Check if cache is expired
    if Time.current - @@cache_timestamps[cache_key] > CACHE_DURATION
      @@options_cache.delete(cache_key)
      @@cache_timestamps.delete(cache_key)
      return nil
    end
    
    @@options_cache[cache_key]
  end
  
  def set_cached_options(cache_key, options)
    @@options_cache[cache_key] = options
    @@cache_timestamps[cache_key] = Time.current
    
    # Clean up old cache entries periodically
    if @@cache_timestamps.size > 100
      cleanup_old_cache_entries
    end
  end
  
  def cleanup_old_cache_entries
    expired_keys = []
    @@cache_timestamps.each do |key, timestamp|
      if Time.current - timestamp > CACHE_DURATION
        expired_keys << key
      end
    end
    
    expired_keys.each do |key|
      @@options_cache.delete(key)
      @@cache_timestamps.delete(key)
    end
    
    Rails.logger.debug "Cleaned up #{expired_keys.size} expired cache entries" if expired_keys.any?
  end
end