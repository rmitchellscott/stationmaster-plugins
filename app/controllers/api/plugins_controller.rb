class Api::PluginsController < Api::BaseController
  def index
    begin
      plugins = PluginDiscoveryService.new.discover_all
      
      render_success({
        plugins: plugins,
        count: plugins.length,
        api_version: '1.0.0',
        last_updated: Time.current.iso8601
      })
      
    rescue => e
      Rails.logger.error "Plugin discovery failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render_error(
        "Failed to discover plugins: #{e.message}",
        status: :internal_server_error,
        details: { error_class: e.class.name }
      )
    end
  end
end