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
    # Load the Base class first
    base_class_file = @plugins_path.join('base.rb')
    if File.exist?(base_class_file)
      base_code = File.read(base_class_file)
      eval(base_code)
      
      # Ensure Rails compatibility for templates
      Base.ensure_rails_compatibility! if defined?(Base)
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
    
    # Use the first matching plugin class
    plugin_class = plugin_classes.first
    plugin_instance = plugin_class.new(settings, trmnl_data)
    
    # Execute the plugin and capture result
    result = if plugin_instance.respond_to?(:locals)
      # Plugin returns locals data directly (new format)
      plugin_instance.locals
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