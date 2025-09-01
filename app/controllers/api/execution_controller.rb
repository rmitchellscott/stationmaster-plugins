class Api::ExecutionController < Api::BaseController
  include ActionView::Rendering
  include ActionController::Helpers
  def execute
    plugin_name = params[:name]
    settings = params[:settings] || {}
    layout = params[:layout] || 'full'
    trmnl_data = params[:trmnl] || {}
    
    begin
      # Execute plugin to get data
      result = PluginExecutorService.new.execute(plugin_name, settings)
      
      if result[:success]
        plugin_data = result[:data] || {}
        
        # Add TRMNL data to plugin data
        plugin_data['trmnl'] = trmnl_data
        
        # Render ERB template with plugin data
        rendered_html = render_erb_template(plugin_name, layout, plugin_data)
        
        if rendered_html
          # Return rendered HTML as plain text
          render plain: rendered_html
        else
          render json: { error: "Template rendering failed - no template found for layout: #{layout}" }, status: :unprocessable_entity
        end
      else
        # Plugin execution failed
        render json: { error: result[:error] || "Plugin execution failed" }, status: :unprocessable_entity
      end
      
    rescue => e
      Rails.logger.error "Plugin execution failed for #{plugin_name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Simple error response
      render json: { error: "Plugin execution failed: #{e.message}" }, status: :internal_server_error
    end
  end
  
  private
  
  def render_erb_template(plugin_name, layout, data)
    # Map layout names to ERB template files
    template_file = case layout
                   when 'full'
                     'full'
                   when 'half_vertical'
                     'half_vertical'
                   when 'half_horizontal' 
                     'half_horizontal'
                   when 'quadrant'
                     'quadrant'
                   else
                     'full' # fallback to full
                   end
    
    # Build template path relative to plugins directory
    template_path = Rails.root.join('app', 'plugins', plugin_name, 'views', template_file + '.html.erb')
    
    unless File.exist?(template_path)
      Rails.logger.error "ERB template not found: #{template_path}"
      return nil
    end
    
    begin
      # Set instance variables for template access
      data.each do |key, value|
        instance_variable_set("@#{key}", value)
      end
      
      # Add plugins directory to Rails view paths temporarily so partials can be found
      # This allows 'plugins/mondrian/common' to resolve correctly  
      plugins_parent_path = Rails.root.join('app').to_s  # Need /app/app to find plugins
      prepend_view_path(plugins_parent_path)
      
      template_path_to_render = "plugins/#{plugin_name}/views/#{template_file}"
      Rails.logger.info "Attempting to render template: #{template_path_to_render}"
      Rails.logger.info "Current view paths: #{view_paths.paths.map(&:to_s)}"
      
      # Use Rails rendering system with detailed error handling
      begin
        Rails.logger.debug "About to render template: #{template_path_to_render}"
        Rails.logger.debug "Available view paths: #{view_paths.paths.map(&:to_s).join(', ')}"
        
        
        rendered_html = render_to_string(template_path_to_render, layout: false, formats: [:html])
        Rails.logger.info "render_to_string succeeded"
        Rails.logger.debug "Raw render_to_string result: #{rendered_html.inspect}"
        Rails.logger.debug "render_to_string result class: #{rendered_html.class}"
      rescue ActionView::MissingTemplate => e
        Rails.logger.error "Template missing: #{e.message}"
        return "TEMPLATE MISSING: #{e.message}"
      rescue ActionView::Template::Error => e
        Rails.logger.error "Template error: #{e.message}"
        Rails.logger.error "Template backtrace: #{e.backtrace.first(5).join('\n')}"
        return "TEMPLATE ERROR: #{e.message}"
      rescue => e
        Rails.logger.error "Other render error: #{e.class} - #{e.message}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
        return "RENDER ERROR: #{e.class} - #{e.message}"
      end
      
      Rails.logger.info "Successfully rendered ERB template: #{template_file} for plugin: #{plugin_name}"
      Rails.logger.info "Rendered HTML length: #{rendered_html.length}"
      Rails.logger.info "Rendered HTML preview: #{rendered_html[0..200]}"
      Rails.logger.info "Rendered HTML inspect: #{rendered_html.inspect}"
      return rendered_html
      
    rescue => e
      Rails.logger.error "ERB template rendering failed: #{e.message}"
      Rails.logger.error "Template path: #{template_path}"
      Rails.logger.error e.backtrace.join("\n")
      return nil
    end
  end
end