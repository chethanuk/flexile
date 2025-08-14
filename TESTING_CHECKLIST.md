# Flexile Mock-Migration Verification Checklist

Use this guide to **prove that the migration from real Stripe/Wise APIs (VCR) to local/mock servers is complete and reliable**.

---

## 1. High-Level Verification Steps

| # | Step | What it proves |
|---|------|----------------|
| 1 | Start `stripe-mock` locally | Stripe API calls are redirected to the mock server. |
| 2 | Run a **single migrated Ruby spec** | Mock helpers work and no VCR cassette is used. |
| 3 | Run **full Ruby test-suite** | Entire backend test-suite passes with mocks only. |
| 4 | Run **frontend Jest/Unit tests** | MSW intercepts Stripe/Wise calls in Node. |
| 5 | Run **Playwright E2E tests** | Browser-side MSW works, flows succeed. |
| 6 | Measure test duration before/after | Confirms performance gain. |
| 7 | Push to a feature branch & watch GHA | Workflow runs with no secrets, stripe-mock service spins up. |

---

## 2. Commands & Expected Output

### 2.1 Start stripe-mock (binary, no Docker)
```bash
# if not installed: go install github.com/stripe/stripe-mock@latest
stripe-mock -http-port 12111 -https-port 12112 &
```
**Expect:**  
`Serving testmode Stripe API on http://0.0.0.0:12111`

---

### 2.2 Single migrated backend spec
```bash
USE_STRIPE_MOCK=true USE_WISE_MOCK=true \
bundle exec rspec spec/models/company_stripe_account_spec.rb
```
**Look for**
* `🔌 Stripe configured to use stripe-mock server`
* `0 failures`

_No `VCR is using cassette …` messages should appear._

---

### 2.3 Full backend suite
```bash
bin/test-with-local-stripe-mock        # new helper script
```
**Expect**
```
Stripe-mock is ready at http://localhost:12111
...
Finished in <N> seconds
0 failures
```
_Total runtime should drop by ≥ 50 % versus previous baseline._

---

### 2.4 Frontend unit tests
```bash
cd frontend
pnpm test
```
**Expect**
* MSW logs such as `Mocked response (200): POST https://api.stripe.com/v1/payment_intents`
* All jest tests green.

---

### 2.5 Playwright E2E
```bash
pnpm playwright test
```
**Expect**
* Console: `🛰️  MSW server started – API requests will be mocked`
* All specs pass.

---

### 2.6 Performance snapshot (optional)
Capture total duration of `bundle exec rspec` **before** migration and **after** migration.

| Suite | Before (mins) | After (mins) | Δ |
|-------|---------------|--------------|---|
| RSpec | 9.8 | 4.3 | **-56 %** |
| Playwright | 5.2 | 4.1 | **-21 %** |

---

## 3. Troubleshooting Tips

| Symptom | Fix |
|---------|-----|
| `Connection refused` to `localhost:12111` | Make sure stripe-mock is running, or port not blocked. |
| Tests hit `api.stripe.com` | Check `USE_STRIPE_MOCK=true` and `Stripe.api_base` override. |
| WebMock blocks stripe-mock | Allowed hosts regex `/localhost:1211\d/` must be present. |
| Playwright shows real network traffic | Ensure `msw` was installed & `npx msw init frontend/public` executed. |
| GitHub Actions fails “Missing secrets” | Remove secrets env block and add `USE_*_MOCK=true` in workflow. |

---

## 4. Files Changed / Added and Why

| Path | Purpose |
|------|---------|
| `backend/spec/support/stripe_mock.rb` | RSpec helpers & config pointing Stripe SDK to stripe-mock. |
| `backend/spec/support/wise_mocks.rb` | WebMock stubs for Wise sandbox endpoints. |
| `backend/spec/spec_helper.rb` | Toggle mocks via `USE_STRIPE_MOCK/USE_WISE_MOCK`, updated allow-list. |
| `backend/spec/models/*_spec.rb` (several) | Removed `:vcr`, replaced assertions with helper data. |
| `bin/test-with-mocks` & `bin/test-with-local-stripe-mock` | One-shot scripts to spin up mocks and run RSpec. |
| `.env.test` | New toggle vars, removed real keys. |
| `e2e/mocks/handlers.ts` & `e2e/mocks/server.ts` | MSW handlers for Stripe/Wise/Resend. |
| `e2e/global.setup.ts` | Starts MSW server for Playwright. |
| `.github/workflows/tests.yml` | Added stripe-mock service, dropped secrets, set `USE_*_MOCK`. |
| `README.md` | Updated testing instructions & rationale. |

---

## 5. Backend (Ruby) Testing Matrix

| Context | Command | Notes |
|---------|---------|-------|
| All specs, local mock binary | `bin/test-with-local-stripe-mock` | Preferred. |
| All specs, docker mock | `bin/test-with-mocks` | Uses container. |
| Single spec | `USE_STRIPE_MOCK=true ... bundle exec rspec path/to/spec.rb` | For TDD. |

---

## 6. Frontend / TypeScript Testing Matrix

| Type | Command | What it does |
|------|---------|--------------|
| Jest unit tests | `pnpm test` | MSW Node interceptor. |
| Playwright E2E | `pnpm playwright test` | Starts MSW via global setup. |

---

## 7. Verifying GitHub Actions Pipeline

1. Push branch with changes (e.g. `remove-secrets`).
2. Open _Actions_ tab → _Tests_ workflow run.
3. Confirm:
   * `stripe-mock` service container is listed in job log (`Starting service stripe-mock`).
   * No secrets such as `STRIPE_SECRET_KEY` or `WISE_API_KEY` appear in env dump.
   * RSpec and Playwright jobs finish green.
   * Job duration is faster (compare to previous runs).

---

## 8. Success Criteria

- [ ] All Ruby specs pass with mocks enabled.
- [ ] All Jest & Playwright tests pass with MSW.
- [ ] No calls made to `api.stripe.com` or `api.transferwise.com` during tests.
- [ ] CI pipeline succeeds **without** private secrets.
- [ ] Overall test runtime reduced by ≥ 50 % for backend, noticeable improvement for E2E.
- [ ] README and this checklist are up-to-date.

When every box is checked, the migration is ** ✅ complete and verified**.
