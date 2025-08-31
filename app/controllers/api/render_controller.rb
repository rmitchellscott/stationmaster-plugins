class Api::RenderController < Api::BaseController
  def render_liquid
    template = params[:template]
    data = params[:data]&.permit! || {}
    
    if template.blank?
      return render_error("Template parameter is required")
    end
    
    begin
      result = LiquidRenderingService.new.render(template, data)
      
      render_success({
        rendered_html: result,
        template_length: template.length,
        data_keys: data.keys
      })
      
    rescue => e
      Rails.logger.error "Liquid rendering failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render_error(
        "Failed to render template: #{e.message}",
        status: :internal_server_error,
        details: { 
          error_class: e.class.name,
          template_preview: template[0..100]
        }
      )
    end
  end
end