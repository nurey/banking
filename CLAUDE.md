# Banking App

## Deployment

Deployed via Kamal to 10.0.0.218. Migrations are not run automatically on deploy.

### Two-phase deploy for migrations

Avoid coupling schema changes with code that depends on them in a single deploy. Instead:

1. Deploy code that works with both old and new schema (e.g., add a column, but don't remove or rename the old one yet)
2. Run migration: `kamal app exec --reuse 'bin/rails db:migrate'`
3. Deploy code that relies on the new schema
4. Clean up the old column in a later migration

This prevents breakage if the deploy fails after the migration has already run.
