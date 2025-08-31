require 'trmnl/liquid'

class LiquidRenderingService
  def initialize
    @liquid_env = TRMNL::Liquid.build_environment
  end

  def render(template_string, data = {})
    # Parse using TRMNL Liquid environment which supports template/render tags
    template = Liquid::Template.parse(template_string, environment: @liquid_env)
    
    # Ensure data is properly formatted for Liquid
    liquid_data = prepare_liquid_data(data)
    
    # Render with the provided data
    rendered = template.render(liquid_data)
    
    rendered
  rescue Liquid::SyntaxError => e
    Rails.logger.error "Liquid syntax error: #{e.message}"
    raise "Invalid template syntax: #{e.message}"
  rescue => e
    Rails.logger.error "Liquid rendering error: #{e.message}"
    raise "Template rendering failed: #{e.message}"
  end

  private

  def prepare_liquid_data(data)
    return {} if data.nil?
    return data if data.is_a?(String)
    
    # Convert to hash with string keys
    case data
    when Hash
      stringify_keys(data)
    when ActionController::Parameters
      stringify_keys(data.to_h)
    else
      { 'data' => data }
    end
  end

  def stringify_keys(hash)
    return hash unless hash.is_a?(Hash)
    
    hash.transform_keys(&:to_s).transform_values do |value|
      value.is_a?(Hash) ? stringify_keys(value) : value
    end
  end
end