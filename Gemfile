source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"
# Use Redis adapter to run Action Cable in production
# gem "redis", ">= 4.0.1"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"

# Additional gems for our plugin service
gem "liquid", "~> 5.0"
gem "trmnl-liquid"
gem "trmnl-i18n"
gem "httparty", "~> 0.21"
gem "chartkick"

# OAuth and Google API gems
gem "signet", "~> 0.19"
gem "oauth2", "~> 2.0"
gem "google-apis-analyticsdata_v1beta", "~> 0.17"
gem "google-apis-calendar_v3", "~> 0.31"
gem "google-apis-youtube_analytics_v2", "~> 0.13"

# Calendar parsing
gem "icalendar", "~> 2.10"
gem "icalendar-recurrence", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false
end
