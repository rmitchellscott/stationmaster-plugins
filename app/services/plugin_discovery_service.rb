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
    template_files = discover_templates(plugin_dir)
    
    {
      name: name.humanize,
      description: extract_description(plugin_content),
      author: "TRMNL",
      version: "1.0.0",
      templates: template_files,
      form_fields: extract_form_fields(plugin_content),
      enabled: true
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
    # Extract settings['key'] patterns from Ruby code to infer form fields
    settings_keys = content.scan(/settings\['([^']+)'\]/).flatten.uniq
    
    return {} if settings_keys.empty?
    
    # Build YAML array structure for form fields based on detected settings
    form_fields = settings_keys.map do |key|
      field_config = {
        'keyname' => key,
        'name' => key.humanize,
        'field_type' => infer_field_type(key, content),
        'description' => "Configuration for #{key.humanize.downcase}"
      }
      
      # Add field-specific configurations
      case field_config['field_type']
      when 'password'
        field_config['placeholder'] = "Enter #{key.humanize.downcase}"
      when 'date'
        field_config['placeholder'] = 'YYYY-MM-DD'
        field_config['help_text'] = "Enter date in YYYY-MM-DD format"
      when 'select'
        options = extract_select_options(key, content)
        if options.any?
          field_config['options'] = options
        else
          # Fallback to text if no options found
          field_config['field_type'] = 'text'
          field_config['placeholder'] = "Enter #{key.humanize.downcase}"
        end
      when 'checkbox'
        field_config['help_text'] = "Check to enable"
      else
        field_config['placeholder'] = "Enter #{key.humanize.downcase}"
      end
      
      field_config
    end
    
    # Convert to YAML array format (like private plugins)
    yaml_content = form_fields.to_yaml.lines.drop(1).join # Remove "---\n" header
    { 'yaml' => yaml_content }
  end

  def discover_templates(plugin_dir)
    templates = {}
    
    # Look for ERB template files in the views directory
    views_dir = File.join(plugin_dir, 'views')
    return templates unless Dir.exist?(views_dir)
    
    template_files = Dir.glob(File.join(views_dir, "*.html.erb")).reject { |f| File.basename(f).start_with?('_') }
    
    template_files.each do |template_file|
      template_name = File.basename(template_file, '.html.erb')
      
      # Map template names to expected layout names
      layout_name = case template_name
                   when 'full'
                     'full'
                   when /half.*vertical/
                     'half_vert'  
                   when /half.*horizontal/
                     'half_horiz'
                   when 'quadrant'
                     'quadrant'
                   else
                     'full' # default to full layout
                   end
      
      # Store placeholder content to indicate layout support
      # This will make database queries show has_full = true, etc.
      templates[layout_name] = 'external'
    end
    
    templates
  end

  def infer_field_type(key, content)
    # Infer field type based on key name and usage patterns
    case key.downcase
    when /token|key|secret|password/
      'password'
    when /date/
      'date'
    when /show_|display_|enable_|disable_/
      # Check if it's a boolean-like field (comparing to 'yes', true, etc.)
      if content.match(/settings\['#{Regexp.escape(key)}'\]\s*==\s*['"]yes['"]/) ||
         content.match(/settings\['#{Regexp.escape(key)}'\]\s*==\s*true/)
        'checkbox'
      else
        'text'
      end
    when /type|mode|format/
      # Check if there are case statements or conditionals that suggest options
      if content.include?("when '") && content.match(/#{Regexp.escape(key)}/)
        'select'
      else
        'text'
      end
    when /url|endpoint/
      'url'
    when /email/
      'email'
    when /count|limit|size|number/
      'number'
    else
      'text'
    end
  end

  def extract_select_options(key, content)
    # Try to extract options from case statements or conditional logic
    options = []
    
    # Look for case statements that use the key
    case_match = content.match(/case\s+#{Regexp.escape(key)}.*?when\s+'([^']+)'.*?when\s+'([^']+)'/m)
    if case_match
      options = case_match.captures
    end
    
    # Fallback to common patterns
    if options.empty?
      case key.downcase
      when /item_type/
        options = ['budgets', 'accounts']
      when /type/
        options = ['default', 'custom']
      end
    end
    
    options
  end
end