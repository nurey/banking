# Flinks CIBC Transaction Auto-Import with User Authentication

## Conventions

- **No co-authored-by lines** in commit messages or PR descriptions
- **No two-phase deploys** during this feature's implementation — migrations and dependent code ship together in each PR
- **httpOnly cookies for auth** — no localStorage, no Bearer tokens, no JWT. The browser handles cookie storage and sending via `credentials: 'include'`

## Context

Currently, importing CIBC/Rogers credit card transactions requires manually downloading CSV files from online banking. The goal is to:
1. Add user authentication so multiple users can register and log in
2. Isolate transactions per user
3. Allow each user to connect their own CIBC account via Flinks
4. Automatically import transactions on a configurable recurring schedule

Three projects are involved:
- **banking** (`~/Devel/banking`) — Rails 8.1 API, GraphQL + REST, PostgreSQL
- **banking-react-apollo** (`~/Devel/banking-react-apollo`) — React 19 + Apollo Client 4 frontend
- **cibc-visa-import** (`~/Devel/cibc-visa-import`) — current manual CSV pipeline (to be superseded)

---

## Architecture Overview

```
┌──────────────────────────────────────────────┐
│  Frontend (React + Apollo)                   │
│  ┌────────────┐ ┌──────────────┐ ┌────────┐ │
│  │ Login /    │ │ Flinks       │ │ Import │ │
│  │ Register   │ │ Connect      │ │ Status │ │
│  └─────┬──────┘ └──────┬───────┘ └───┬────┘ │
└────────┼───────────────┼─────────────┼───────┘
  Bearer │ token  loginId│      GraphQL│
         ▼               ▼             ▼
┌──────────────────────────────────────────────┐
│  Backend (Rails 8.1 API)                     │
│                                              │
│  Auth: Rails 8 built-in (session tokens)     │
│  POST /registration, POST /session           │
│                                              │
│  Flinks::Client ─► Flinks::TransactionImporter│
│       │                     │                │
│  FlinksImportJob (Solid Queue, daily 6am)    │
│                             ▼                │
│  ┌──────────────────────────────────────┐    │
│  │ PostgreSQL                           │    │
│  │ users ──< flinks_connections         │    │
│  │ users ──< credit_card_transactions   │    │
│  │            ──< notes                 │    │
│  │            ──< credits_debits        │    │
│  └──────────────────────────────────────┘    │
└──────────────────────────────────────────────┘
```

---

## Part 1: User Authentication

### Approach: Rails 8 built-in auth generator + httpOnly cookies

**Why the built-in generator:** Rails 8.1 ships with `bin/rails generate authentication` which creates a complete session-based auth system. We adapt it for API-only mode with JSON responses.

**Why httpOnly cookies (not Bearer tokens or JWT):** Production uses HTTPS (Kamal proxy terminates SSL), so `SameSite=None; Secure` cookies work cross-origin. httpOnly cookies can't be read by JavaScript, eliminating XSS token theft. The browser handles cookie storage and sending automatically — no localStorage, no token management in the frontend.

**Why not Devise:** Overkill for this app — one user table, no OAuth, no confirmable/lockable.

### What the generator creates (adapted for API-only)

| File | Purpose |
|------|---------|
| `app/models/user.rb` | `has_secure_password`, `has_many :sessions`, `normalizes :email_address` |
| `app/models/session.rb` | Session record (user_id, ip_address, user_agent, token) |
| `app/models/current.rb` | Thread-local `Current.user` / `Current.session` |
| `app/controllers/concerns/authentication.rb` | `require_authentication`, session lookup via signed `session_id` cookie, returns 401 JSON (not redirect) |
| `app/controllers/sessions_controller.rb` | `GET /session` (whoami), `POST /session` (login), `DELETE /session` (logout) — all JSON |
| `app/controllers/passwords_controller.rb` | Password reset (JSON) |
| `db/migrate/*_create_users.rb` | `email_address` (unique), `password_digest` |
| `db/migrate/*_create_sessions.rb` | `user_id`, `token`, `ip_address`, `user_agent` |

### What we add on top

| File | Purpose |
|------|---------|
| `app/controllers/registrations_controller.rb` | `POST /registration` — create user + session, set cookie, return JSON |
| `config/application.rb` | Add `ActionDispatch::Cookies` and `ActionDispatch::Session::CookieStore` middleware (stripped by `api_only`) |
| `app/controllers/application_controller.rb` | Include `ActionController::Cookies` |
| `config/initializers/cors.rb` | `credentials: true`, specific origin (not wildcard) |

### Cookie details

- `cookies.signed.permanent[:session_id]` — signed by Rails (tamper-proof), httpOnly (no JS access), Secure in production, `SameSite=None` in production (cross-origin)
- Session lookup: `Session.find_by(id: cookies.signed[:session_id])`
- Frontend checks auth status via `GET /session` on page load (returns 200 with user or 401)

### Auth in GraphQL + REST

- The `Authentication` concern is included in `ApplicationController` — all controllers get `require_authentication` and `current_user`
- `GraphqlController#execute` passes `Current.user` into GraphQL context
- All resolvers scope queries through `context[:current_user]`
- All REST controller actions scope through `Current.user`
- Missing/invalid cookie → 401 response (handled by the concern)

### Frontend files

| File | Purpose |
|------|---------|
| `src/components/LoginPage.jsx` | Email + password form |
| `src/components/RegisterPage.jsx` | Registration form |
| `src/hooks/useAuth.jsx` | Auth state via `GET /session` check — `login()`, `register()`, `logout()`, `isAuthenticated`, `user`, `loading` |

**Apollo Client change** (`src/index.jsx`) — just `credentials: 'include'`, no auth headers:
```js
const httpLink = new HttpLink({
  uri: import.meta.env.VITE_GRAPHQL_URI,
  credentials: 'include',
});
```

**Routing:** `react-router-dom` with `ProtectedRoute` (redirect to `/login` if unauthenticated) and `PublicRoute` (redirect to `/` if already authenticated).

---

## Part 2: Per-User Transaction Isolation

### Approach: `user_id` column on `credit_card_transactions`

No `default_scope` (Rails footgun). Explicit scoping in resolvers and controllers via `current_user.credit_card_transactions`.

`notes` and `credits_debits` are already scoped through their FK to `credit_card_transactions` — no `user_id` needed on those tables.

### Unique index changes

Current indexes reject duplicates globally. Two users with the same transaction would conflict. Replace with user-scoped indexes:

```sql
-- Drop existing
DROP INDEX credit_card_transactions_debits_unique_key;
DROP INDEX credit_card_transactions_credits_unique_key;

-- Create user-scoped
CREATE UNIQUE INDEX credit_card_transactions_debits_unique_key
  ON credit_card_transactions (user_id, tx_date, details, debit) WHERE credit IS NULL;
CREATE UNIQUE INDEX credit_card_transactions_credits_unique_key
  ON credit_card_transactions (user_id, tx_date, details, credit) WHERE debit IS NULL;
```

### Migration strategy (two-phase deploy per CLAUDE.md)

**Phase 1:** Add `user_id` as nullable, create `users` table
- Migration: `create_table :users`
- Migration: `add_reference :credit_card_transactions, :user, null: true`
- Deploy — existing code still works (nullable column, no scoping yet)

**Phase 2:** Seed admin user, backfill, enforce NOT NULL, replace indexes
- Rake task: create admin user, `UPDATE credit_card_transactions SET user_id = <admin_id>`
- Migration: `change_column_null :credit_card_transactions, :user_id, false`
- Migration: drop old indexes, create user-scoped indexes
- Deploy with auth enforcement + scoped queries

### GraphQL resolver changes

`app/graphql/types/query_type.rb` — scope through current_user:
```ruby
def credit_card_transactions(**options)
  scope = context[:current_user].credit_card_transactions
    .where(tx_date: 12.months.ago..)
  # ... existing sort/filter logic
end
```

Mutations (`update_credit_card_transaction`, `create_note`) — verify ownership:
```ruby
tx = context[:current_user].credit_card_transactions.find_by!(id: id)
```

REST controllers — same pattern with `current_user.credit_card_transactions`.

---

## Part 3: Flinks Integration

### Database: `flinks_connections` table

```sql
CREATE TABLE flinks_connections (
  id            bigserial PRIMARY KEY,
  user_id       bigint NOT NULL REFERENCES users(id),
  institution   text NOT NULL,
  login_id      text NOT NULL,     -- encrypted at rest
  request_id    text,              -- encrypted at rest
  last_synced_at timestamptz,
  status        text NOT NULL DEFAULT 'active',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, institution)
);
```

**Token encryption:** Use Rails 8 `encrypts` attribute:
```ruby
class FlinksConnection < ApplicationRecord
  belongs_to :user
  encrypts :login_id
  encrypts :request_id
end
```

Keys generated via `bin/rails db:encryption:init`, stored in `config/credentials.yml.enc`.

### Flinks HTTP Client

**`app/services/flinks/client.rb`** — raw `Net::HTTP` (not the archived gem):
- `authorize(login_id:)` → exchange for access token
- `fetch_transactions(account_id:, from:, to:)` → GET transactions

**`app/services/flinks/errors.rb`** — `ApiError`, `AuthenticationError`, `RateLimitError`

### Transaction Importer

**`app/services/flinks/transaction_importer.rb`**:
1. Accept a `FlinksConnection` record
2. Fetch transactions (default: last 7 days)
3. Transform:
   - `TransactionDate` → `tx_date`
   - `Description` → `details`
   - Positive amount → `debit = (amount * 100).round`, `credit = NULL`
   - Negative amount → `credit = (amount.abs * 100).round`, `debit = NULL`
   - Connection's card info → `card_number`
   - Connection's `user_id` → `user_id`
4. `CreditCardTransaction.insert_all(records)` — unique indexes handle dedup via ON CONFLICT
5. Return `{ imported: N, skipped: N }`

### Recurring Job

**`app/jobs/flinks_import_job.rb`**:
```ruby
class FlinksImportJob < ApplicationJob
  queue_as :default
  retry_on Flinks::ApiError, wait: :polynomially_longer, attempts: 5
  discard_on Flinks::AuthenticationError

  def perform(days_back: 7)
    FlinksConnection.where(status: 'active').find_each do |conn|
      Flinks::TransactionImporter.new(conn).import(days_back:)
    end
  end
end
```

**`config/recurring.yml`**:
```yaml
flinks_import:
  class: FlinksImportJob
  schedule: every day at 6am America/Toronto
  args:
    days_back: 7
```

### Solid Queue setup

1. Uncomment `require "active_job/railtie"` in `config/application.rb`
2. Add `gem "solid_queue"` to Gemfile
3. `bin/rails solid_queue:install`
4. Set `config.active_job.queue_adapter = :solid_queue` in production.rb
5. Add `SOLID_QUEUE_IN_PUMA: "1"` to `config/deploy.yml` env

### Frontend: Flinks Connect

**`src/components/FlinksConnect.jsx`** — modal with Flinks Connect iframe widget for one-time bank auth. On success, sends `loginId` to backend.

**`src/components/ImportStatus.jsx`** — shows last sync time, connection status, "Sync Now" button.

### GraphQL additions

- Query: `flinksConnections` → list user's connected accounts
- Query: `flinksImportStatus` → last run, next scheduled
- Mutation: `createFlinksConnection(loginId, institution)` → store connection
- Mutation: `triggerFlinksImport(daysBack)` → enqueue job on demand
- Mutation: `deleteFlinksConnection(id)` → remove connection

### Polling over webhooks

The backend runs without SSL (`proxy: ssl: false` in deploy.yml). Flinks webhooks require HTTPS. Daily polling with 7-day overlap + dedup indexes is simpler and sufficient.

---

## Development Approach: Test-Driven Development

Each feature follows a strict red-green-refactor cycle:
1. **Red:** Write a failing test that specifies the desired behavior
2. **Green:** Write the minimum code to make the test pass
3. **Refactor:** Clean up while keeping tests green

Within each PR, the commit history should reflect this rhythm — test commits precede implementation commits. Every behavior is specified by a test before the code exists.

### Testing Philosophy

1. **Don't test upstream behavior.** If Rails, ActiveRecord, or a gem already tests it (validations, associations, `has_secure_password`, `normalizes`), don't write a spec for it. Only test custom behavior and integration contracts.
2. **Minimize mocking/stubbing.** Use real objects, real database, real ActiveRecord queries. Mocks hide bugs where the mock diverges from reality. Only mock when there is no practical alternative (e.g., time-dependent behavior with `travel_to`).
3. **VCR cassettes for network interaction.** All tests that hit the Flinks API record real HTTP interactions as VCR cassettes (`spec/cassettes/`). Tests replay cassettes on subsequent runs — no stubs, no hand-crafted response hashes. Record new cassettes by running tests with `VCR_RECORD=new_episodes`. Add `gem 'vcr'` and `gem 'webmock'` to the test group.
4. **Real database, no mocked queries.** Integration specs hit PostgreSQL. This catches issues with unique indexes, constraints, and scoping that mocks would hide.
5. **Fixtures for test data.** Follow the existing pattern in `spec/fixtures/`. Add `users.yml` and `flinks_connections.yml` fixtures.

### Backend TDD (RSpec)

For each backend feature, write tests first in this order:
1. **Request/integration specs** — define the API contract (endpoints, status codes, response shape)
2. **Service specs** — define inputs, outputs, and error cases (VCR cassettes for Flinks HTTP)
3. **GraphQL specs** — define query/mutation behavior (following existing patterns in `spec/graphql/`)
4. **Model specs** — only for custom logic (computed fields, custom scopes, non-trivial methods). Skip for standard Rails declarations.

### Frontend TDD (Vitest)

For each frontend feature, write tests first:
1. **Hook tests** — define auth state transitions (`useAuth` login/logout/token expiry)
2. **Component tests** — define rendering and interaction behavior (login form submission, error display, protected route redirect)

The project uses Vitest (`vitest run`). Add `@testing-library/react` for component tests.

---

## Implementation Sequence (Stacked PRs)

Each PR targets the branch of the previous PR, forming a dependent chain. Merge bottom-up (PR1 first). Each PR is independently reviewable and deployable following the two-phase deploy protocol in CLAUDE.md.

```
main
 └─ PR1: feat/user-auth-backend
     └─ PR2: feat/transaction-isolation
         └─ PR3: feat/auth-frontend
             └─ PR4: feat/flinks-connection
                 └─ PR5: feat/flinks-import-pipeline
                     └─ PR6: feat/flinks-frontend
```

### PR1: `feat/user-auth-backend` → `main`
**Users + session-token authentication (backend only)**

Tests first (red):
1. `spec/requests/auth_spec.rb` — register returns 201 + token; login returns 200 + token; login with wrong password returns 401; register with duplicate email returns 422; request without token returns 401; logout invalidates session

Then implementation (green):
3. Run `bin/rails generate authentication` — creates User, Session, Current models, Authentication concern, SessionsController, PasswordsController, migrations
4. Adapt generated code for API-only + httpOnly cookies: JSON responses (not redirects), `cookies.signed[:session_id]` lookup, add cookie middleware to `config/application.rb`, include `ActionController::Cookies` in ApplicationController
5. `app/controllers/registrations_controller.rb` — `POST /registration` (generator doesn't include signup)
6. `app/controllers/sessions_controller.rb` — add `GET /session` (whoami) action
7. `config/routes.rb` — add `resource :registration, only: :create`, add `:show` to session
8. `config/initializers/cors.rb` — `credentials: true`, specific origin
9. Pass `Current.user` into GraphQL context in `graphql_controller.rb`

- **Deploy note:** Auth endpoints exist but nothing requires auth yet. Existing API continues to work unauthenticated.

### PR2: `feat/transaction-isolation` → `feat/user-auth-backend`
**Per-user transaction scoping (backend only)**

Tests first (red):
1. `spec/graphql/queries/credit_card_transactions_query_spec.rb` — update existing specs: user A cannot see user B's transactions; unauthenticated request returns error
2. `spec/graphql/mutations/update_credit_card_transaction_mutation_spec.rb` — update: cannot update another user's transaction
3. `spec/graphql/mutations/create_note_mutation_spec.rb` — update: cannot annotate another user's transaction
4. `spec/requests/credit_card_transactions_spec.rb` — REST endpoints return only current user's transactions
5. `spec/models/credit_card_transaction_spec.rb` — user-scoped uniqueness (same tx for different users is allowed, same tx for same user is rejected)

Then implementation (green):
6. Migration: add nullable `user_id` FK to `credit_card_transactions`
7. `lib/tasks/admin.rake` — seed admin user, backfill existing transactions
8. Migration: enforce `user_id` NOT NULL, replace unique indexes with user-scoped versions
9. Scope all GraphQL resolvers (`query_type.rb`) through `context[:current_user]`
10. Scope all REST controller actions through `current_user`
11. Scope mutations — verify ownership
12. Pass `current_user` into GraphQL context in `graphql_controller.rb`
13. Require authentication on all endpoints (except `/auth/*`)
14. Lock down CORS origins in `cors.rb`
15. Update fixtures to include `user_id`

- **Deploy note:** After this PR, the API requires authentication via session cookie.

### PR3: `feat/auth-frontend` → `feat/transaction-isolation`
**Login/register UI + protected routes (frontend)**

Tests first (red):
1. `src/hooks/useAuth.test.jsx` — session check on mount sets isAuthenticated; login sets user on success; login throws on invalid credentials; logout clears user

Then implementation (green):
2. Add `react-router-dom`, `@testing-library/react` dependencies
3. `src/hooks/useAuth.jsx` — auth state via `GET /session` on mount, `login()`, `register()`, `logout()` with `credentials: 'include'`, no localStorage
4. `src/components/LoginPage.jsx` — email + password form
5. `src/components/RegisterPage.jsx` — registration form
6. `src/index.jsx` — Apollo HttpLink with `credentials: 'include'`, BrowserRouter, AuthProvider wrapping
7. `src/components/App.jsx` — ProtectedRoute/PublicRoute wrappers, react-router-dom Routes
8. `src/components/AppNavbar.jsx` — user email display, logout button

- **Deploy note:** Can deploy frontend before or after PR2, but the app will require login once both are live.

### PR4: `feat/flinks-connection` → `feat/auth-frontend`
**Flinks account connection (backend + frontend)**

Tests first (red):
1. `spec/services/flinks/client_spec.rb` (VCR cassettes) — authorize returns request_id; fetch_transactions returns parsed transactions; handles 401 with AuthenticationError; handles 429 with RateLimitError; handles network timeout with ApiError
2. `spec/graphql/mutations/create_flinks_connection_mutation_spec.rb` — stores connection for current user; rejects duplicate institution
3. `spec/graphql/mutations/delete_flinks_connection_mutation_spec.rb` — deletes own connection; cannot delete another user's connection

Then implementation (green):
5. Migration: create `flinks_connections` table with encrypted columns
6. `app/models/flinks_connection.rb` — `belongs_to :user`, `encrypts :login_id, :request_id`
7. Generate Active Record encryption keys via `bin/rails db:encryption:init`
8. `app/services/flinks/client.rb` — `Net::HTTP` wrapper for Flinks API
9. `app/services/flinks/errors.rb` — error classes
10. `app/graphql/types/flinks_connection_type.rb`
11. `app/graphql/mutations/create_flinks_connection.rb` — store loginId from Flinks Connect
12. `app/graphql/mutations/delete_flinks_connection.rb` — remove connection
13. `src/components/FlinksConnect.jsx` — Flinks Connect iframe widget in modal

- **Deploy note:** Users can now connect their CIBC account. No imports yet.

### PR5: `feat/flinks-import-pipeline` → `feat/flinks-connection`
**Automated transaction import (backend)**

Tests first (red):
1. `spec/services/flinks/transaction_importer_spec.rb` (VCR cassettes for API calls, real DB for insert/dedup) — transforms positive amount to debit in cents; transforms negative amount to credit in cents; sets user_id from connection; skips duplicates via ON CONFLICT; returns imported/skipped counts; handles empty response; handles partial failures
2. `spec/jobs/flinks_import_job_spec.rb` — iterates active connections; skips inactive connections; retries on ApiError; discards on AuthenticationError
3. `spec/graphql/mutations/trigger_flinks_import_mutation_spec.rb` — enqueues job for current user
4. `spec/graphql/queries/flinks_import_status_query_spec.rb` — returns last sync time and status

Then implementation (green):
5. `app/services/flinks/transaction_importer.rb` — fetch, transform, insert
6. `app/jobs/flinks_import_job.rb` — iterates active connections, imports transactions
7. `config/recurring.yml` — daily 6am ET schedule
8. Enable Solid Queue: uncomment `active_job/railtie`, add `solid_queue` gem, install, configure
9. `config/deploy.yml` — add `SOLID_QUEUE_IN_PUMA` env var
10. `app/graphql/types/flinks_import_status_type.rb`
11. `app/graphql/mutations/trigger_flinks_import.rb` — on-demand sync
12. GraphQL query: `flinksImportStatus` — last run, next scheduled

- **Deploy note:** Two-phase — deploy Solid Queue migration first, then deploy code. After this, imports run automatically.

### PR6: `feat/flinks-frontend` → `feat/flinks-import-pipeline`
**Import status UI + manual trigger (frontend)**

Tests first (red):
1. `src/components/ImportStatus.test.jsx` — renders last sync time; renders "never" when no syncs; "Sync Now" button triggers mutation; shows loading state during sync
2. `src/components/FlinksConnect.test.jsx` — renders iframe; calls mutation on success callback; shows error on failure

Then implementation (green):
3. `src/components/ImportStatus.jsx` — last sync time, connection status, "Sync Now" button
4. Integrate into App.jsx / dashboard view
5. Connection management UI (list connected accounts, disconnect)

- **Deploy note:** Pure frontend, safe to deploy anytime after PR5.

---

## Files Summary

### New files (banking)
| File | Purpose |
|------|---------|
| `app/models/user.rb` | `has_secure_password`, associations (generated) |
| `app/models/session.rb` | Token-based session record (generated) |
| `app/models/current.rb` | Thread-local `Current.user` (generated) |
| `app/controllers/concerns/authentication.rb` | `require_authentication`, token lookup (generated) |
| `app/controllers/sessions_controller.rb` | Login/logout (generated) |
| `app/controllers/passwords_controller.rb` | Password reset (generated) |
| `app/controllers/registrations_controller.rb` | User signup (custom) |
| `db/migrate/*_create_users.rb` | Users table (generated) |
| `db/migrate/*_create_sessions.rb` | Sessions table (generated) |
| `db/migrate/*_add_user_id_to_credit_card_transactions.rb` | User FK (nullable) |
| `db/migrate/*_enforce_user_id_and_update_indexes.rb` | NOT NULL + scoped indexes |
| `db/migrate/*_create_flinks_connections.rb` | Flinks tokens table |
| `app/models/flinks_connection.rb` | Encrypted tokens, belongs_to :user |
| `app/services/flinks/client.rb` | HTTP client for Flinks API |
| `app/services/flinks/errors.rb` | Error classes |
| `app/services/flinks/transaction_importer.rb` | Transform + insert |
| `app/jobs/flinks_import_job.rb` | Recurring sync job |
| `config/recurring.yml` | Solid Queue schedule |
| `app/graphql/types/flinks_connection_type.rb` | GQL type |
| `app/graphql/types/flinks_import_status_type.rb` | GQL type |
| `app/graphql/mutations/create_flinks_connection.rb` | Store connection |
| `app/graphql/mutations/trigger_flinks_import.rb` | On-demand sync |
| `app/graphql/mutations/delete_flinks_connection.rb` | Remove connection |
| `spec/services/flinks/*_spec.rb` | Client + importer tests |
| `lib/tasks/admin.rake` | Seed admin user + backfill |

### Modified files (banking)
| File | Change |
|------|--------|
| `Gemfile` | Add `solid_queue`, `vcr`, `webmock`, `bcrypt` (added by auth generator) |
| `config/application.rb` | Uncomment `active_job/railtie` |
| `config/routes.rb` | Auth routes (generated), registration route, Flinks callback |
| `config/environments/production.rb` | `queue_adapter = :solid_queue` |
| `config/deploy.yml` | Add `SOLID_QUEUE_IN_PUMA` env |
| `app/controllers/application_controller.rb` | Include `Authentication` concern (generated) |
| `app/controllers/graphql_controller.rb` | Pass `Current.user` to context |
| `app/controllers/credit_card_transactions_controller.rb` | Scope through user |
| `app/graphql/types/query_type.rb` | Scope queries through user |
| `app/graphql/types/mutation_type.rb` | Add new mutations |
| `app/graphql/mutations/create_note.rb` | Verify ownership |
| `app/graphql/mutations/update_credit_card_transaction.rb` | Verify ownership |
| `config/initializers/cors.rb` | Lock down origins |

### New files (banking-react-apollo)
| File | Purpose |
|------|---------|
| `src/components/LoginPage.jsx` | Login form (POST /session) |
| `src/components/RegisterPage.jsx` | Registration form (POST /registration) |
| `src/hooks/useAuth.jsx` | Auth context — login, register, logout via httpOnly cookies (no localStorage) |
| `src/components/FlinksConnect.jsx` | Bank connection widget |
| `src/components/ImportStatus.jsx` | Sync status + manual trigger |

### Modified files (banking-react-apollo)
| File | Change |
|------|--------|
| `package.json` | Add `react-router-dom` |
| `src/index.jsx` | Apollo `credentials: 'include'`, BrowserRouter, AuthProvider |
| `src/components/App.jsx` | Protected routes, import status |
| `src/components/AppNavbar.jsx` | User email, logout, settings |

---

## Security Audit Findings

Address before shipping. Integrate fixes into the relevant PRs.

### CRITICAL

**CSRF with `SameSite=None` cookies.** CORS only prevents reading the response — it does not block the request. Any website can forge `POST /graphql` mutations and the browser attaches the session cookie. Fix: add Origin header verification as a `before_action` on `ApplicationController` — reject non-GET requests where `request.headers['Origin']` doesn't match the allowed origin.

- File: `app/controllers/application_controller.rb`
- Belongs in: PR1

### HIGH

**Sessions never expire.** `cookies.signed.permanent` sets a 20-year cookie and `find_session_by_cookie` has no TTL check. Fix: use a session-lifetime cookie (drop `permanent`), add server-side expiry check (e.g., `Session.where(created_at: 30.days.ago..)` in the lookup).

- Files: `app/controllers/concerns/authentication.rb`, `app/models/session.rb`
- Belongs in: PR1

**Hardcoded "changeme" password in migration.** The bcrypt hash is committed to version control. Fix: change the admin user password immediately after deploy. For future seed data, use a rake task that reads from credentials or prompts for input.

- File: `db/migrate/20260414161031_add_user_id_to_credit_card_transactions.rb`
- Belongs in: PR2 (or manual post-deploy step)

### MEDIUM

**No minimum password length.** Users can register with a 1-character password. Fix: add `validates :password, length: { minimum: 8 }, if: -> { password.present? }` to User model.

- File: `app/models/user.rb`
- Belongs in: PR1

**No rate limiting on registration.** `SessionsController` has rate limiting but `RegistrationsController` does not. Fix: add `rate_limit to: 5, within: 10.minutes, only: :create`.

- File: `app/controllers/registrations_controller.rb`
- Belongs in: PR1

**GraphQL introspection enabled in production.** Full schema discoverable. Fix: add `disable_introspection_entry_points if Rails.env.production?` to schema.

- File: `app/graphql/banking_schema.rb`
- Belongs in: PR2

**No GraphQL depth/complexity limits.** DoS vector. Fix: add `max_depth 10` and `max_complexity 200` to schema.

- File: `app/graphql/banking_schema.rb`
- Belongs in: PR2

**Passwords route overly broad.** `resources :passwords` creates 7 routes, only `update` is implemented. Fix: restrict to `resource :password, only: [:update], param: :token`.

- File: `config/routes.rb`
- Belongs in: PR1

**Flinks `triggerFlinksImport` must be scoped** to the current user's connections, not all active connections.

- Belongs in: PR5

### LOW

**Unused `token` column on sessions.** `find_session_by_cookie` looks up by `id` via signed cookie, not by `token`. Remove the column or repurpose it.

- File: `app/models/session.rb`, `db/migrate/*_create_sessions.rb`
- Belongs in: PR1

**`config.hosts` not configured in production.** Add `config.hosts = ["budgetr.nurey.com"]` for defense-in-depth.

- File: `config/environments/production.rb`
- Belongs in: PR1

**GraphQL `RecordNotFound` handling.** `find_by!` in mutations may produce raw exception messages instead of clean GraphQL errors. Verify and add `rescue_from` if needed.

- Files: `app/graphql/mutations/create_note.rb`, `app/graphql/mutations/update_credit_card_transaction.rb`
- Belongs in: PR2

---

## Verification

1. **Auth:** Register user via curl, login, verify session cookie is set, `GET /session` returns user
2. **CSRF:** Verify that a cross-origin POST without matching Origin header is rejected
3. **Session expiry:** Verify that expired sessions return 401
4. **Isolation:** Create two users, import transactions for each, verify they only see their own
5. **Backfill:** Run admin rake task, verify all existing transactions have `user_id`
6. **Dedup:** Run Flinks import twice, verify no duplicate transactions
7. **Recurring:** Check Solid Queue logs for scheduled 6am runs
8. **Frontend:** Login flow, Flinks Connect widget, transaction list loads, import status shows
