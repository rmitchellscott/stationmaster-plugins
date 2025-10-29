# Stationmaster Plugins

Rails API service for rendering Liquid templates and executing plugins for the Stationmaster platform.

## Liquid Rendering

Parse Liquid templates with data via POST to `/api/render`:

```bash
curl -X POST http://localhost:3000/api/render \
  -H "Content-Type: application/json" \
  -d '{
    "template": "Hello {{ name }}!",
    "data": { "name": "World" }
  }'
```

Returns `rendered_html` with the parsed template.

## API Endpoints

### Plugin Discovery
- `GET /api/plugins` - List all available plugins with metadata

### Plugin Execution
- `POST /api/plugins/:name/execute` - Execute plugin and render template
  - Params: `settings` (plugin config), `layout` (full/half_vertical/half_horizontal/quadrant), `trmnl` (user context)
  - Returns: Rendered HTML for the specified layout

### Dynamic Options
- `POST /api/plugins/:plugin_identifier/options/:field_name` - Fetch dynamic field options
  - Params: `oauth_tokens`, `user` data
  - Returns: Available options for dropdowns/selects (cached 5 min)

### Template Rendering
- `POST /api/render` - Parse Liquid template with data
  - Params: `template`, `data`
  - Returns: `rendered_html`

### Health Check
- `GET /api/health` - Service health status

## Plugin Structure

Plugins live in `app/plugins/` with this structure:
```
app/plugins/plugin_name/
  ├── plugin_name.rb          # Main plugin class (inherits from Base)
  ├── form_fields.yaml        # Plugin configuration schema
  └── views/
      ├── full.html.erb
      ├── half_vertical.html.erb
      ├── half_horizontal.html.erb
      └── quadrant.html.erb
```

All plugins inherit from `Base` (app/plugins/base.rb:1) and implement `locals` method to return template data.

## Development

Rails 8.0+, Ruby 3.3+. Uses Liquid 5.0, supports OAuth flows for Google Calendar, Todoist, YouTube Analytics, and other integrations.
