# App Dist Format

An `app-dist` is the final directory structure that gets zipped and released.

Package scripts should create:

```text
work/<package>/app-dist/
```

The contents inside `app-dist` are app-specific. Templates normally live in:

```text
packages/<package>/templates/
```

Generated archives are written to:

```text
artifacts/<package>.zip
```

The zip should contain the app-dist contents at its root unless a package later
needs a wrapper folder.

