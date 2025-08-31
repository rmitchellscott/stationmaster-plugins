class Api::BaseController < ApplicationController
  # Common functionality for all API controllers
  
  private
  
  def render_success(data = {})
    render json: {
      success: true,
      data: data,
      timestamp: Time.current.iso8601
    }
  end
  
  def render_error(message, status: :unprocessable_entity, details: nil)
    error_response = {
      success: false,
      error: message,
      timestamp: Time.current.iso8601
    }
    error_response[:details] = details if details.present?
    
    render json: error_response, status: status
  end
end