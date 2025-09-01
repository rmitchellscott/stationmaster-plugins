class Api::ExecutionController < Api::BaseController
  include ActionView::Rendering
  include ActionController::Helpers
  
  # Ensure API-only behavior
  before_action :set_api_headers
  
  def execute
    plugin_name = params[:name]
    settings = transform_checkbox_values(params[:settings] || {})
    layout = params[:layout] || 'full'
    trmnl_data = params[:trmnl] || {}
    
    Rails.logger.info "=== GitHub Plugin Debug ==="
    Rails.logger.info "Plugin name: #{plugin_name}"
    Rails.logger.info "Settings: #{settings.inspect}"
    Rails.logger.info "GITHUB_API_TOKEN present: #{!ENV['GITHUB_API_TOKEN'].nil?}"
    Rails.logger.info "GITHUB_API_TOKEN length: #{ENV['GITHUB_API_TOKEN']&.length}"
    Rails.logger.info "Rails credentials plugins: #{Rails.application.credentials.plugins rescue 'ERROR accessing credentials.plugins'}"
    
    begin
      # Execute plugin to get data
      Rails.logger.info "About to execute plugin: #{plugin_name}"
      result = PluginExecutorService.new.execute(plugin_name, settings, trmnl_data)
      Rails.logger.info "Plugin execution result: success=#{result[:success]}, error=#{result[:error]}"
      
      if result[:success]
        plugin_data = result[:data] || {}
        
        # Add TRMNL data to plugin data
        plugin_data['trmnl'] = trmnl_data
        
        # Add instance_name for template access
        plugin_data['instance_name'] = trmnl_data.dig('plugin_settings', 'instance_name') || 'Plugin Instance'
        
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
  
  def set_api_headers
    response.headers['Content-Type'] = 'application/json' unless params[:action] == 'execute' && request.format == :html
  end
  
  # Transform boolean values to strings that Ruby plugins expect
  def transform_checkbox_values(settings)
    settings.transform_values do |value|
      case value
      when true then 'yes'
      when false then 'no'
      else value
      end
    end
  end

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
      
      # Define helper methods in the current binding so they're available in ERB
      def git_commit_grayscale(count)
        case count.to_i
        when 0
          'bg--gray-7'
        when 1..2
          'bg--gray-5'
        when 3..5
          'bg--gray-4'
        when 6..10
          'bg--gray-3'
        when 11..15
          'bg--gray-2'
        else
          'bg--gray-1'
        end
      end
      
      # Add plugins directory to Rails view paths temporarily so partials can be found
      # Problem: Templates call render 'plugins/plugin_name/partial_name'  
      # Rails looks for: [VIEW_PATH]/plugins/plugin_name/_partial_name.html.erb
      # Actual file is at: app/plugins/plugin_name/views/_partial_name.html.erb
      
      app_path = Rails.root.join('app').to_s
      prepend_view_path(app_path)
      
      # Solution: Create a temporary directory structure that Rails can resolve
      # We'll create symbolic links from plugins/plugin_name/* to plugins/plugin_name/views/*
      plugins_dir = Rails.root.join('app', 'plugins')
      
      Dir.glob(plugins_dir.join('*')).each do |plugin_path|
        next unless File.directory?(plugin_path)
        
        plugin_dir_name = File.basename(plugin_path)
        views_dir = File.join(plugin_path, 'views')
        
        if Dir.exist?(views_dir)
          # Create symlinks for each partial in the views directory to be accessible directly in plugin dir
          Dir.glob(File.join(views_dir, '_*.html.erb')).each do |partial_path|
            partial_name = File.basename(partial_path)
            target_path = File.join(plugin_path, partial_name)
            
            # Create symlink if it doesn't exist
            unless File.exist?(target_path)
              begin
                File.symlink(File.join('views', partial_name), target_path)
                Rails.logger.debug "Created symlink: #{target_path} -> views/#{partial_name}"
              rescue => e
                Rails.logger.warn "Failed to create symlink for #{partial_name}: #{e.message}"
              end
            end
          end
        end
      end
      
      template_path_to_render = "plugins/#{plugin_name}/views/#{template_file}"
      Rails.logger.info "Attempting to render template: #{template_path_to_render}"
      Rails.logger.info "Current view paths: #{view_paths.paths.map(&:to_s)}"
      
      # Use Rails rendering system with detailed error handling
      begin
        Rails.logger.debug "About to render template: #{template_path_to_render}"
        Rails.logger.debug "Available view paths: #{view_paths.paths.map(&:to_s).join(', ')}"
        
        # Pass plugin data as local variables to the ERB template
        rendered_html = render_to_string(template_path_to_render, layout: false, formats: [:html], locals: data)
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