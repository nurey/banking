# Flinks CIBC Transaction Auto-Import with User Authentication

## Conventions

- **No co-authored-by lines** in commit messages or PR descriptions

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

### Approach: Rails 8 built-in authentication generator (`--api`)

**Why the built-in generator:** Rails 8.1 ships with `bin/rails generate authentication --api` which creates a complete token-based auth system. It uses server-side session tokens (stored in a `sessions` table) sent via `Authorization: Bearer <token>` headers — works identically with Apollo Client. No custom JWT code to maintain.

**Why not JWT:** The generator provides revocable tokens (delete the session row), session tracking (IP, user agent), and password reset — all out of the box. JWT requires a custom implementation, can't be revoked without a blocklist, and needs secret key management.

**Why not Devise:** Overkill for this app — one user table, no OAuth, no confirmable/lockable.

### What the generator creates

| File | Purpose |
|------|---------|
| `app/models/user.rb` | `has_secure_password`, `has_many :sessions`, `normalizes :email_address` |
| `app/models/session.rb` | Token-based session record (user_id, ip_address, user_agent) |
| `app/models/current.rb` | Thread-local `Current.user` / `Current.session` |
| `app/controllers/concerns/authentication.rb` | `require_authentication`, `current_user`, token lookup via `Authorization: Bearer` |
| `app/controllers/sessions_controller.rb` | `POST /session` (login), `DELETE /session` (logout) |
| `app/controllers/passwords_controller.rb` | Password reset endpoints |
| `db/migrate/*_create_users.rb` | `email_address` (unique), `password_digest` |
| `db/migrate/*_create_sessions.rb` | `user_id`, `ip_address`, `user_agent` |

### What we add on top

| File | Purpose |
|------|---------|
| `app/controllers/registrations_controller.rb` | `POST /registration` — create user + session, return token |

The generator does not include registration. We add a single controller for that.

### Database tables

```sql
-- Created by generator
CREATE TABLE users (
  id               bigserial PRIMARY KEY,
  email_address    varchar NOT NULL,
  password_digest  varchar NOT NULL,
  created_at       timestamptz NOT NULL,
  updated_at       timestamptz NOT NULL,
  UNIQUE(email_address)
);

CREATE TABLE sessions (
  id         bigserial PRIMARY KEY,
  user_id    bigint NOT NULL REFERENCES users(id),
  ip_address varchar,
  user_agent varchar,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);
```

### Auth in GraphQL + REST

- The `Authentication` concern is included in `ApplicationController` — all controllers get `require_authentication` and `current_user`
- `GraphqlController#execute` passes `Current.user` into GraphQL context
- All resolvers scope queries through `context[:current_user]`
- All REST controller actions scope through `Current.user`
- Missing/invalid token → 401 response (handled by the concern)

### Frontend files

| File | Purpose |
|------|---------|
| `src/components/LoginPage.jsx` | Email + password form, stores session token in localStorage |
| `src/components/RegisterPage.jsx` | Registration form |
| `src/hooks/useAuth.js` | Auth state context — `login()`, `logout()`, `isAuthenticated` |

**Apollo Client change** (`src/index.jsx`):
```js
import { setContext } from '@apollo/client/link/context';

const authLink = setContext((_, { headers }) => ({
  headers: {
    ...headers,
    authorization: localStorage.getItem('token')
      ? `Bearer ${localStorage.getItem('token')}`
      : '',
  },
}));

const client = new ApolloClient({
  link: authLink.concat(httpLink),
  cache: new InMemoryCache(),
});
```

**Routing:** Add `react-router-dom` for login/register/dashboard pages. Unauthenticated users → login page. 401 from API → clear token, redirect to login.

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
4. `app/controllers/registrations_controller.rb` — `POST /registration` (generator doesn't include signup)
5. `config/routes.rb` — add `resource :registration, only: :create`
6. Pass `Current.user` into GraphQL context in `graphql_controller.rb`

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

- **Deploy note:** Two-phase — deploy migration + backfill first, then deploy auth enforcement. After this PR, the API requires a JWT.

### PR3: `feat/auth-frontend` → `feat/transaction-isolation`
**Login/register UI + protected routes (frontend)**

Tests first (red):
1. `src/hooks/useAuth.test.js` — login stores session token, logout calls DELETE /session and clears token, isAuthenticated reflects state
2. `src/components/LoginPage.test.jsx` — renders form, submits credentials to POST /session, shows error on failure, redirects on success
3. `src/components/RegisterPage.test.jsx` — renders form, submits to POST /registration, shows error on duplicate email

Then implementation (green):
4. Add `react-router-dom`, `@testing-library/react` dependencies
5. `src/hooks/useAuth.js` — auth context, `login()` (POST /session), `register()` (POST /registration), `logout()` (DELETE /session), `isAuthenticated`
6. `src/components/LoginPage.jsx` — email + password form
7. `src/components/RegisterPage.jsx` — registration form
8. `src/index.jsx` — Apollo `setContext` auth link with Bearer token, error link for 401 → redirect
9. `src/components/App.jsx` — route setup, protected routes
10. `src/components/AppNavbar.jsx` — user email display, logout button

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
| `Gemfile` | Add `solid_queue`, `vcr`, `webmock`; uncomment `bcrypt` |
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
| `src/hooks/useAuth.js` | Auth context — login, register, logout, token in localStorage |
| `src/components/FlinksConnect.jsx` | Bank connection widget |
| `src/components/ImportStatus.jsx` | Sync status + manual trigger |

### Modified files (banking-react-apollo)
| File | Change |
|------|--------|
| `package.json` | Add `react-router-dom` |
| `src/index.jsx` | Apollo auth link, router setup |
| `src/components/App.jsx` | Protected routes, import status |
| `src/components/AppNavbar.jsx` | User email, logout, settings |

---

## Verification

1. **Auth:** Register user via curl, login, use session token to query GraphQL — verify scoped results
2. **Isolation:** Create two users, import transactions for each, verify they only see their own
3. **Backfill:** Run admin rake task, verify all existing transactions have `user_id`
4. **Dedup:** Run Flinks import twice, verify no duplicate transactions
5. **Recurring:** Check Solid Queue logs for scheduled 6am runs
6. **Frontend:** Login flow, Flinks Connect widget, transaction list loads, import status shows
