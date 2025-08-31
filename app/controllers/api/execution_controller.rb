class Api::ExecutionController < Api::BaseController
  def execute
    plugin_name = params[:name]
    settings = params[:settings] || {}
    
    begin
      result = PluginExecutorService.new.execute(plugin_name, settings)
      
      if result[:success]
        # Return raw locals data directly for universal compatibility
        render json: result[:data]
      else
        # Simple error response
        render json: { error: result[:error] || "Plugin execution failed" }, status: :unprocessable_entity
      end
      
    rescue => e
      Rails.logger.error "Plugin execution failed for #{plugin_name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Simple error response
      render json: { error: "Plugin execution failed: #{e.message}" }, status: :internal_server_error
    end
  end
end