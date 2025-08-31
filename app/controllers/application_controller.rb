class ApplicationController < ActionController::API
  def index
    render json: {
      service: 'External Plugin Service',
      version: '1.0.0',
      description: 'Stateless plugin execution service for external plugin discovery',
      endpoints: {
        health: '/api/health',
        plugins: '/api/plugins - Returns plugin metadata with templates and schemas',
        execute: '/api/plugins/:name/execute - Returns raw plugin data (JSON)',
        render: '/api/render - Renders Liquid templates with data'
      },
      note: 'Plugin execution returns raw JSON data compatible with private plugin polling',
      timestamp: Time.current.iso8601
    }
  end
end
