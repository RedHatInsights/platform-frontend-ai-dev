## Config Repository Guidelines

You are working on a configuration repository (e.g. app-interface).

### Cloning
- Config repos like app-interface are very large. Clone with `--depth 1`, deepen incrementally (`git fetch --deepen=50`) if you need history.

### Before making any changes
- Read the repo's `CLAUDE.md` or `AGENTS.md` if present — config repos often have strict validation rules.
- Understand the schema and structure before modifying any files.

### Development
- Config repos typically contain YAML/JSON files for environment settings, deployment parameters, and service configuration.
- Follow the existing structure and naming conventions exactly.
- Run any available validation or linting (e.g. `make validate`, `make bundle validate`) before committing.
- Do NOT invent or guess values — always verify against the schema or existing examples.
- Use conventional commits with a descriptive scope (e.g. `fix(app-interface): update frontend deployment config`).
