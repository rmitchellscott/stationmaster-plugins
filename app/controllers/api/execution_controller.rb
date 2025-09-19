class Api::ExecutionController < Api::BaseController
  include ActionView::Rendering
  include ActionController::Helpers

  # Ensure API-only behavior
  before_action :set_api_headers
  before_action :inject_full_calendar_license
  
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

        # Add plugin_name for template access (needed by title_bar partial)
        plugin_data['plugin_name'] = plugin_name

        # Add instance_name for template access
        plugin_data['instance_name'] = trmnl_data.dig('plugin_settings', 'instance_name') || 'Plugin Instance'
        
        # Render ERB template with plugin data
        rendered_html = render_erb_template(plugin_name, layout, plugin_data)
        
        if rendered_html
          # Return rendered HTML properly
          render html: rendered_html.html_safe, layout: false
        else
          render json: { error: "Template rendering failed - no template found for layout: #{layout}" }, status: :unprocessable_content, formats: [:json]
        end
      else
        # Plugin execution failed - force JSON format for error response
        render json: { error: result[:error] || "Plugin execution failed" }, status: :unprocessable_content, formats: [:json]
      end
      
    rescue => e
      Rails.logger.error "Plugin execution failed for #{plugin_name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Simple error response - force JSON format
      render json: { error: "Plugin execution failed: #{e.message}" }, status: :internal_server_error, formats: [:json]
    end
  end
  
  private

  def set_api_headers
    # Set JSON content type for error responses, but allow HTML for successful template rendering
    unless params[:action] == 'execute' && request.format == :html
      response.headers['Content-Type'] = 'application/json'
    end
  end

  def inject_full_calendar_license
    # Inject GPL license key for FullCalendar if not already present
    if Rails.application.credentials.plugins && !Rails.application.credentials.plugins[:full_calendar]
      # Create a new hash with the existing plugins and add full_calendar
      plugins_with_license = Rails.application.credentials.plugins.to_h.merge(
        full_calendar: { license_key: 'GPL-My-Project-Is-Open-Source' }
      )

      # Replace the plugins hash with our extended version
      Rails.application.credentials.plugins.define_singleton_method(:full_calendar) do
        OpenStruct.new(license_key: 'GPL-My-Project-Is-Open-Source')
      end
    end
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
      
      # Create helper module and include it in ActionView::Base so methods are available in templates
      helper_module = Module.new do
        def git_commit_grayscale(count)
          # GitHub contribution levels with refined ranges
          case count.to_i
          when 0
            'bg-white'      # No contributions
          when 1..3
            'bg--gray-5'    # Low activity
          when 4..7
            'bg--gray-4'    # Medium-low activity
          when 8..10
            'bg--gray-3'    # Medium activity
          when 11..20
            'bg--gray-2'    # Medium-high activity
          else
            'bg-black'      # High activity (20+)
          end
        end
        
        def format_number(number)
          return "0" if number.nil?

          # Convert to integer or float as appropriate
          num = number.is_a?(String) ? number.to_f : number

          # Handle decimals - if it's a whole number, format as integer
          if num == num.to_i
            num.to_i.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,')
          else
            # Format with 2 decimal places and add commas
            ("%.2f" % num).gsub(/(\d)(?=(\d{3})+\.)/, '\1,')
          end
        end

        def formulate_and_group_events_by_day(events, today_in_tz, days_to_show)
          Rails.logger.info "formulate_and_group_events_by_day called with today_in_tz: #{today_in_tz.inspect} (class: #{today_in_tz.class}), events count: #{events.size}"
          # Handle different date input types
          today = case today_in_tz
                  when String
                    Date.parse(today_in_tz)
                  when Date
                    today_in_tz
                  else
                    today_in_tz.to_date  # Handle TimeWithZone, Time, DateTime
                  end
          Rails.logger.info "Converted today to: #{today.inspect}"

          # Generate the date range for the number of days to show
          date_range = (0...days_to_show).map { |i| today + i.days }

          # Group events by their date
          grouped_events = {}

          date_range.each do |date|
            # Format the date - use a default format since we don't have access to date_format helper here
            formatted_date = date.strftime('%A, %B %-d')

            # Find events for this date
            day_events = events.select do |event|
              Rails.logger.info "Event date_time class: #{event[:date_time].class.name}"
              event_date = case event[:date_time].class.name
                          when 'Date'
                            event[:date_time]
                          when 'String'
                            Date.parse(event[:date_time])
                          when 'Time', 'DateTime', 'ActiveSupport::TimeWithZone'
                            event[:date_time].to_date
                          else
                            Rails.logger.warn "Unknown date_time type: #{event[:date_time].class} - #{event[:date_time].inspect}"
                            next
                          end
              Rails.logger.info "Comparing event date #{event_date} (#{event[:summary]}) with #{date}"
              event_date == date
            end

            grouped_events[formatted_date] = day_events
          end

          grouped_events
        end
      end
      
      # Include helper methods in ActionView::Base so they're available to render_to_string
      ActionView::Base.include(helper_module)
      
      # Add plugins directory to Rails view paths temporarily so partials can be found
      # Problem: Templates call render 'plugins/plugin_name/partial_name' or 'lib/plugin_name/views/shared/partial_name'
      # Rails looks for: [VIEW_PATH]/plugins/plugin_name/_partial_name.html.erb
      # Actual file is at: app/plugins/plugin_name/views/_partial_name.html.erb
      
      app_path = Rails.root.join('app').to_s
      prepend_view_path(app_path)
      
      # Also create lib symlink to plugins for templates that expect lib/ paths
      lib_path = Rails.root.join('app', 'lib')
      plugins_path = Rails.root.join('app', 'plugins')
      
      unless File.exist?(lib_path)
        begin
          File.symlink(plugins_path.to_s, lib_path.to_s)
          Rails.logger.debug "Created symlink: #{lib_path} -> #{plugins_path}"
        rescue => e
          Rails.logger.warn "Failed to create lib->plugins symlink: #{e.message}"
        end
      end
      
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
