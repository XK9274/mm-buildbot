# Package Config

Each package has a `package.yml` file:

```yaml
id: example-app
name: Example App
version: manual
source:
  repo: https://github.com/example/example-app.git
  ref: main
app_dist:
  template: packages/example-app/templates
  output_name: ExampleApp
tokens:
  APP_ID: example-app
  APP_NAME: Example App
```

Required fields:

- `id`
- `name`
- `source.repo`
- `source.ref`
- `app_dist.template`

The scripts intentionally keep the package format small for now. More fields can
be added once real package examples are available.

