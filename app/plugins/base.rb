class Base
  # Base class for all plugins
  # Plugins should inherit from this and implement the `locals` method
  
  def initialize(settings = {})
    @settings = settings || {}
  end
  
  # Main method that should be implemented by plugins
  # Returns a hash of data to be used in template rendering
  def locals
    raise NotImplementedError, "#{self.class} must implement #locals method"
  end
  
  # Helper method for making HTTP requests
  def fetch_data(url, headers = {})
    HTTParty.get(url, headers: headers)
  rescue => e
    Rails.logger.error "Failed to fetch data from #{url}: #{e.message}"
    nil
  end
  
  # Helper method for getting current time
  def current_time
    Time.current
  end
  
  # Helper method for formatting time
  def format_time(time, format = "%I:%M %p")
    time.strftime(format)
  end
  
  # Helper method for accessing settings
  def setting(key, default = nil)
    @settings[key.to_s] || @settings[key.to_sym] || default
  end
  
  private
  
  attr_reader :settings
end