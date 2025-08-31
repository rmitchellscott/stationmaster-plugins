class PluginDiscoveryService
  def initialize
    @plugins_path = Rails.root.join('app', 'plugins')
  end

  def discover_all
    plugins = {}
    
    return plugins unless Dir.exist?(@plugins_path)
    
    # Scan for plugin directories
    Dir.glob(@plugins_path.join('*')).each do |plugin_dir|
      next unless File.directory?(plugin_dir)
      
      plugin_name = File.basename(plugin_dir)
      plugin_metadata = discover_plugin(plugin_name, plugin_dir)
      
      if plugin_metadata
        plugins[plugin_name] = plugin_metadata
      end
    end
    
    plugins
  rescue => e
    Rails.logger.error "Plugin discovery failed: #{e.message}"
    raise "Failed to discover plugins: #{e.message}"
  end

  private

  def discover_plugin(name, plugin_dir)
    # Look for the main plugin file
    plugin_file = File.join(plugin_dir, "#{name}.rb")
    
    unless File.exist?(plugin_file)
      Rails.logger.warn "Plugin file not found: #{plugin_file}"
      return nil
    end

    # Read and analyze the plugin file to extract metadata
    plugin_content = File.read(plugin_file)
    
    {
      name: name,
      type: 'external',
      file_path: plugin_file,
      description: extract_description(plugin_content),
      form_fields: extract_form_fields(plugin_content),
      template_path: extract_template_path(plugin_dir),
      last_modified: File.mtime(plugin_file).iso8601
    }
  end

  def extract_description(content)
    # Look for class comment or description
    if match = content.match(/# Description: (.+)/i)
      match[1].strip
    elsif match = content.match(/class\s+\w+.*\n\s*#\s*(.+)/m)
      match[1].strip
    else
      "Plugin description not available"
    end
  end

  def extract_form_fields(content)
    # Look for form field definitions or return empty for now
    # This could be enhanced to parse actual field definitions
    []
  end

  def extract_template_path(plugin_dir)
    template_file = Dir.glob(File.join(plugin_dir, "*.liquid")).first
    template_file ? File.basename(template_file) : "#{File.basename(plugin_dir)}.liquid"
  end
end