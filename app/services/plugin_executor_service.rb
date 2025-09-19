class PluginExecutorService
  def initialize
    @plugins_path = Rails.root.join('app', 'plugins')
  end

  def execute(plugin_name, settings = {}, trmnl_data = {})
    plugin_dir = @plugins_path.join(plugin_name)
    plugin_file = plugin_dir.join("#{plugin_name}.rb")
    
    unless File.exist?(plugin_file)
      return { success: false, error: "Plugin not found: #{plugin_name}" }
    end

    begin
      # Load the plugin file
      plugin_code = File.read(plugin_file)
      
      # Execute the plugin in a safe environment
      result = execute_plugin_code(plugin_code, plugin_name, settings, trmnl_data)
      
      { success: true, data: result }
    rescue => e
      Rails.logger.error "Plugin execution failed for #{plugin_name}: #{e.message}"
      { success: false, error: e.message }
    end
  end

  private

  def execute_plugin_code(plugin_code, plugin_name, settings, trmnl_data)
    # Load the Base class first (needed for OAuthTokenCache access)
    base_class_file = @plugins_path.join('base.rb')
    if File.exist?(base_class_file)
      base_code = File.read(base_class_file)
      eval(base_code)

      # Ensure Rails compatibility for templates
      Base.ensure_rails_compatibility! if defined?(Base)
    end

    # Load helper files if they exist for this plugin
    helpers_dir = @plugins_path.join(plugin_name, 'helpers')
    if Dir.exist?(helpers_dir)
      Dir.glob(helpers_dir.join('*.rb')).each do |helper_file|
        helper_code = File.read(helper_file)
        eval(helper_code)
      end
    end

    # Create a safe execution environment
    plugin_module = Module.new

    # Evaluate the plugin code within the module
    plugin_module.module_eval(plugin_code)
    
    # Look for plugin class (convention: plugin name in CamelCase)
    plugin_class_name = plugin_name.camelize
    
    # Debug logging
    Rails.logger.info "Looking for plugin class: #{plugin_class_name}"
    Rails.logger.info "Plugin module constants: #{plugin_module.constants}"
    Rails.logger.info "Global Plugins constants: #{defined?(Plugins) ? Plugins.constants : 'Plugins not defined'}"
    
    plugin_classes = find_plugin_classes(plugin_module, plugin_class_name)
    
    Rails.logger.info "Found plugin classes: #{plugin_classes.map(&:name)}"
    
    if plugin_classes.empty?
      raise "No plugin class found in #{plugin_name}"
    end
    
    # Merge OAuth tokens into settings if present
    # OAuth plugins expect credentials in settings[plugin_name]
    # Only inject OAuth tokens for plugins that actually need them
    oauth_plugins = %w[google_calendar youtube_analytics google_analytics todoist]

    if trmnl_data['oauth_tokens'].present? && oauth_plugins.include?(plugin_name)
      oauth_tokens = trmnl_data['oauth_tokens']
      
      # OAuth tokens might be keyed by provider (e.g., 'google') not plugin name
      # Map provider to plugin name
      provider_mapping = {
        'google_analytics' => 'google',
        'youtube_analytics' => 'google',
        'todoist' => 'todoist'
      }
      
      provider = provider_mapping[plugin_name] || plugin_name
      
      # Try different ways to access the tokens
      # Handle ActionController::Parameters as well as Hash
      if oauth_tokens.is_a?(Hash) || oauth_tokens.is_a?(ActionController::Parameters)
        # Convert to regular hash if it's ActionController::Parameters
        oauth_hash = oauth_tokens.is_a?(ActionController::Parameters) ? oauth_tokens.to_unsafe_h : oauth_tokens
        
        # Try plugin name first
        if oauth_hash[plugin_name].present?
          token_data = oauth_hash[plugin_name]
          # Get access token from cache if we have refresh token
          if token_data['refresh_token'].present? && trmnl_data['user'] && trmnl_data['user']['id']
            user_id = trmnl_data['user']['id']
            access_token = Base::OAuthTokenCache.get_or_refresh(user_id, provider, token_data['refresh_token'])
            token_data['access_token'] = access_token if access_token
          end
          settings[plugin_name] = token_data
        # Try provider name
        elsif oauth_hash[provider].present?
          token_data = oauth_hash[provider]
          # Get access token from cache if we have refresh token
          if token_data['refresh_token'].present? && trmnl_data['user'] && trmnl_data['user']['id']
            user_id = trmnl_data['user']['id']
            access_token = Base::OAuthTokenCache.get_or_refresh(user_id, provider, token_data['refresh_token'])
            token_data['access_token'] = access_token if access_token
          end
          settings[plugin_name] = token_data
        # If there's only one key, use that
        elsif oauth_hash.keys.length == 1
          key = oauth_hash.keys.first
          token_data = oauth_hash[key]
          # Get access token from cache if we have refresh token
          if token_data['refresh_token'].present? && trmnl_data['user'] && trmnl_data['user']['id']
            user_id = trmnl_data['user']['id']
            # Guess provider from plugin name if needed
            token_provider = provider || key
            access_token = Base::OAuthTokenCache.get_or_refresh(user_id, token_provider, token_data['refresh_token'])
            token_data['access_token'] = access_token if access_token
          end
          settings[plugin_name] = token_data
        else
          Rails.logger.warn "No OAuth tokens found for #{plugin_name} or provider #{provider}"
        end
      end
    end
    
    # Use the first matching plugin class
    plugin_class = plugin_classes.first
    Rails.logger.info "Final settings being passed to plugin: #{settings.inspect}"
    Rails.logger.info "Settings keys: #{settings.keys}"
    Rails.logger.info "Settings['google_calendar']: #{settings['google_calendar'].inspect}"
    plugin_instance = plugin_class.new(settings, trmnl_data)

    # Execute the plugin and capture result
    result = if plugin_instance.respond_to?(:locals)
      # Plugin returns locals data directly (new format)
      Rails.logger.info "Calling locals method on plugin instance"
      locals_result = plugin_instance.locals
      Rails.logger.info "Locals result keys: #{locals_result.keys rescue 'error'}"
      Rails.logger.info "Events in locals: #{locals_result[:events].inspect rescue 'error getting events'}" if locals_result.is_a?(Hash)
      locals_result
    elsif plugin_instance.respond_to?(:execute)
      # Plugin has execute method
      plugin_instance.execute(settings)
    elsif plugin_instance.respond_to?(:call)
      # Plugin is callable
      plugin_instance.call(settings)
    else
      raise "Plugin class must implement 'locals', 'execute', or 'call' method"
    end
    
    # Aggressive cleanup after plugin execution
    cleanup_plugin_memory(plugin_module, plugin_instance, plugin_class)
    
    result
  end

  def find_plugin_classes(plugin_module, expected_name)
    classes = []
    
    # Check direct constants in plugin_module
    plugin_module.constants.each do |const_name|
      const = plugin_module.const_get(const_name)
      if const.is_a?(Class)
        Rails.logger.info "Found class in plugin_module: #{const.name}"
        classes << const
      elsif const.is_a?(Module)
        # Check nested modules (like Plugins module)
        Rails.logger.info "Found module in plugin_module: #{const.name}"
        const.constants.each do |nested_const_name|
          nested_const = const.const_get(nested_const_name)
          if nested_const.is_a?(Class)
            Rails.logger.info "Found nested class: #{nested_const.name}"
            classes << nested_const
          end
        end
      end
    end
    
    # Also check global Plugins module if it exists
    if defined?(Plugins)
      Rails.logger.info "Checking global Plugins module"
      Plugins.constants.each do |const_name|
        const = Plugins.const_get(const_name)
        if const.is_a?(Class)
          Rails.logger.info "Found class in global Plugins: #{const.name}"
          classes << const
        end
      end
    end
    
    classes
  end

  def cleanup_plugin_memory(plugin_module, plugin_instance, plugin_class)
    # Clear instance variables from plugin instance
    plugin_instance.instance_variables.each do |var|
      plugin_instance.remove_instance_variable(var)
    end
    
    # Remove constants from plugin module to free memory
    plugin_module.constants.each do |const_name|
      begin
        plugin_module.send(:remove_const, const_name)
      rescue NameError
        # Constant may have been removed already, ignore
      end
    end
    
    # Clean up global Plugins module if classes were added there
    if defined?(Plugins)
      Plugins.constants.each do |const_name|
        const = Plugins.const_get(const_name)
        if const.is_a?(Class) && const == plugin_class
          begin
            Plugins.send(:remove_const, const_name)
          rescue NameError
            # Constant may have been removed already, ignore
          end
        end
      end
    end
    
    # Force garbage collection to immediately reclaim memory
    GC.start
  rescue => e
    Rails.logger.warn "Plugin cleanup failed: #{e.message}"
    # Continue execution even if cleanup fails
  end
end