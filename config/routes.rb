Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes for plugin service
  namespace :api, defaults: { format: :json } do
    # Plugin discovery and metadata
    get 'plugins', to: 'plugins#index'
    
    # Plugin execution
    post 'plugins/:name/execute', to: 'execution#execute'
    
    # Template rendering  
    post 'render', to: 'render#render_liquid'
    
    # Health check for service monitoring
    get 'health', to: 'health#index'
  end

  # Root path returns service information
  root 'application#index'
end
