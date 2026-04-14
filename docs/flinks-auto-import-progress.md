# Flinks Auto-Import — Implementation Progress

## PR Stack

```
main
 └─ PR1: feat/user-auth-backend        ✅ done
     └─ PR2: feat/transaction-isolation ✅ done
         └─ PR3: feat/auth-frontend     ✅ done (banking-react-apollo repo)
             └─ PR4: feat/flinks-connection         ⬜ not started
                 └─ PR5: feat/flinks-import-pipeline ⬜ not started
                     └─ PR6: feat/flinks-frontend    ⬜ not started
```

## PR1: User auth backend — `feat/user-auth-backend`
**Repo:** banking | **Status:** complete | **Tests:** 16 pass

- [x] Rails 8 auth generator (User, Session, Current models)
- [x] Adapted for API-only: JSON responses, httpOnly signed cookies, cookie middleware
- [x] RegistrationsController (`POST /registration`)
- [x] SessionsController with `GET /session` (whoami), `POST /session` (login), `DELETE /session` (logout)
- [x] CSRF protection via Origin header verification (`verify_origin` before_action)
- [x] CORS `credentials: true` with specific origin
- [x] 30-day session expiry (server-side check + cookie `expires`)
- [x] Request specs: registration, login, logout, session check, cookie auth, CSRF (3 tests), session expiry (2 tests)

## PR2: Transaction isolation — `feat/transaction-isolation`
**Repo:** banking | **Status:** complete | **Tests:** 43 pass (cumulative)

- [x] Migration: `user_id` on `credit_card_transactions` (NOT NULL, FK)
- [x] Backfill existing data to `ilia@lobsanov.com` (migration requires `ADMIN_PASSWORD` env var)
- [x] User-scoped unique indexes (replacing global ones)
- [x] `belongs_to :user` on CreditCardTransaction, `has_many :credit_card_transactions` on User
- [x] Scoped GraphQL queries (`creditCardTransactions`, `notes`) through `context[:current_user]`
- [x] Scoped mutations (`updateCreditCardTransaction`, `createNote`) — ownership verified
- [x] Scoped REST controller through `Current.user.credit_card_transactions`
- [x] Updated all existing specs to pass `current_user` in context
- [x] Isolation specs: user A can't see user B's data (GraphQL + REST)
- [x] Mutation isolation specs: can't modify another user's transactions

## PR3: Auth frontend — `feat/auth-frontend`
**Repo:** banking-react-apollo | **Status:** complete | **Tests:** 10 pass

- [x] `useAuth` hook: cookie-based auth, `GET /session` on mount, login/register/logout
- [x] `useAuth` tests (5 tests): session check, login success/failure, logout
- [x] `LoginPage` component
- [x] `RegisterPage` component
- [x] `App.jsx` with react-router-dom: `ProtectedRoute`, `PublicRoute`
- [x] `AppNavbar` with user email + logout
- [x] Apollo Client `credentials: 'include'`
- [x] Vitest + @testing-library/react setup

## PR4: Flinks connection — `feat/flinks-connection`
**Repo:** banking + banking-react-apollo | **Status:** not started

- [ ] Migration: `flinks_connections` table with encrypted columns
- [ ] `FlinksConnection` model with `encrypts :login_id, :request_id`
- [ ] `Flinks::Client` HTTP wrapper (VCR cassettes for tests)
- [ ] `Flinks::Errors` classes
- [ ] GraphQL mutations: `createFlinksConnection`, `deleteFlinksConnection`
- [ ] `FlinksConnect` frontend component (iframe widget)
- [ ] Specs

## PR5: Flinks import pipeline — `feat/flinks-import-pipeline`
**Repo:** banking | **Status:** not started

- [ ] `Flinks::TransactionImporter` service
- [ ] `FlinksImportJob` (Solid Queue recurring)
- [ ] `config/recurring.yml` — daily 6am ET
- [ ] Enable Solid Queue (uncomment `active_job/railtie`, add gem, configure)
- [ ] GraphQL: `flinksImportStatus` query, `triggerFlinksImport` mutation (scoped to current user)
- [ ] Specs (VCR + real DB)

## PR6: Flinks frontend — `feat/flinks-frontend`
**Repo:** banking-react-apollo | **Status:** not started

- [ ] `ImportStatus` component (last sync, "Sync Now" button)
- [ ] Connection management UI (list, disconnect)
- [ ] Integration into dashboard

## Security Audit Fixes

| Finding | Severity | Status | PR |
|---------|----------|--------|----|
| CSRF via Origin verification | CRITICAL | ✅ fixed | PR1 |
| Sessions never expire | HIGH | ✅ fixed | PR1 |
| Hardcoded "changeme" password | HIGH | ✅ fixed | PR2 |
| No minimum password length | MEDIUM | ⬜ todo | PR1 |
| No registration rate limiting | MEDIUM | ⬜ todo | PR1 |
| GraphQL introspection in prod | MEDIUM | ⬜ todo | PR2 |
| GraphQL depth/complexity limits | MEDIUM | ⬜ todo | PR2 |
| Passwords route overly broad | MEDIUM | ⬜ todo | PR1 |
| Flinks import scoped to user | MEDIUM | ⬜ todo | PR5 |
| Unused token column on sessions | LOW | ⬜ todo | PR1 |
| config.hosts not configured | LOW | ⬜ todo | PR1 |
| GraphQL RecordNotFound handling | LOW | ⬜ todo | PR2 |
