class PluginExecutorService
  def initialize
    @plugins_path = Rails.root.join('app', 'plugins')
  end

  def execute(plugin_name, settings = {})
    plugin_dir = @plugins_path.join(plugin_name)
    plugin_file = plugin_dir.join("#{plugin_name}.rb")
    
    unless File.exist?(plugin_file)
      return { success: false, error: "Plugin not found: #{plugin_name}" }
    end

    begin
      # Load the plugin file
      plugin_code = File.read(plugin_file)
      
      # Execute the plugin in a safe environment
      result = execute_plugin_code(plugin_code, plugin_name, settings)
      
      { success: true, data: result }
    rescue => e
      Rails.logger.error "Plugin execution failed for #{plugin_name}: #{e.message}"
      { success: false, error: e.message }
    end
  end

  private

  def execute_plugin_code(plugin_code, plugin_name, settings)
    # Create a safe execution environment
    plugin_module = Module.new
    
    # Evaluate the plugin code within the module
    plugin_module.module_eval(plugin_code)
    
    # Look for plugin class (convention: plugin name in CamelCase)
    plugin_class_name = plugin_name.camelize
    plugin_classes = find_plugin_classes(plugin_module, plugin_class_name)
    
    if plugin_classes.empty?
      raise "No plugin class found in #{plugin_name}"
    end
    
    # Use the first matching plugin class
    plugin_class = plugin_classes.first
    plugin_instance = plugin_class.new
    
    # Execute the plugin
    if plugin_instance.respond_to?(:locals)
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
  end

  def find_plugin_classes(plugin_module, expected_name)
    classes = []
    
    plugin_module.constants.each do |const_name|
      const = plugin_module.const_get(const_name)
      if const.is_a?(Class)
        classes << const
      end
    end
    
    # Also check nested modules (like Plugins::RoutePlanner)
    if defined?(Plugins)
      Plugins.constants.each do |const_name|
        const = Plugins.const_get(const_name)
        if const.is_a?(Class)
          classes << const
        end
      end
    end
    
    classes
  end
end