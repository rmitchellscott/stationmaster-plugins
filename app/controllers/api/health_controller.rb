class Api::HealthController < Api::BaseController
  def index
    render_success({
      service: 'stationmaster-plugins',
      status: 'healthy',
      version: '1.0.0',
      plugins_count: plugin_count,
      uptime: uptime_seconds
    })
  end
  
  private
  
  def plugin_count
    # Count available plugins from the plugins directory
    return 0 unless Dir.exist?(Rails.root.join('app', 'plugins'))
    
    Dir.glob(Rails.root.join('app', 'plugins', '*')).select { |f| File.directory?(f) }.count
  end
  
  def uptime_seconds
    # Simple uptime calculation - time since Rails loaded
    Time.current.to_i - Rails.application.config.start_time.to_i
  rescue
    0
  end
end