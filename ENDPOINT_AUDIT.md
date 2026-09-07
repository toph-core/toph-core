# Endpoint audit — POS against the deployed API

Date: 2026-09-07.

## What "deployed" means here

Not `master`. The live API at `https://api.maryaidev.uz/` serves
`/api/v1/branch-shifts` (401, i.e. the group exists) and does **not** serve
`/api/v1/auth/register` (404). Only `feat/branch-shifts` (`2efa99f`, one commit
ahead of `origin/master`) registers the first and drops the second, so that is
the build in production and the baseline every claim below is measured against.

`origin/master` (`ee263bd`) has no `branch_shifts` table, routes or triggers at
all. If anything is ever rolled back to it, the whole branch-shift flow —
open, close, and the replicated row every terminal reads — 404s. Do not deploy
`master` over the current build.

Route table read from `app/internal/handler/handler.go`; request/response
shapes from `app/internal/model/*.go`; role gates from
`app/internal/middleware/rbac.go`.

## Fixed in this pass

| # | Symptom against the deployed API | Cause | Fix |
|---|---|---|---|
| 1 | `POST /api/v1/auth/register` → **404**; a staff member created in Settings never reached the server and the queued write quarantined | The route was deliberately removed ("staff users are created via POST /api/v1/users by admins") | `ListAPI.authRegister` → `ListAPI.usersCreate` = `api/v1/users` |
| 2 | `PUT /api/v1/users/{id}` → **405**; every staff edit quarantined | The route is registered `PATCH`. The handler's Swagger annotation said `[put]`, so the docs agreed with the client and both were wrong | Client sends `PATCH`; the annotation and the regenerated `swagger.*` now say `patch` |
| 3 | Staff create bound to nothing server-side ("full_name is required"), and the provisional local row showed a nameless user | The form sent `fullName` / `phoneNumber`; `model.CreateStaffRequest` is snake_case | `full_name` / `phone_number` |
| 4 | Creating or editing a **time-based** table → **400**, so the table stayed on one terminal | `price_per_hour` went out as a Dart `double`, which `jsonEncode` renders `50000.0`; the deployed `PricePerHour` is `*int64` and Go will not decode a fractional number into it | Parsed with `int.tryParse`. No precision is lost — `_ThousandsFormatter` strips everything but digits — and an int also binds to the `*float64` the API is moving to |
| 5 | `POST /api/v1/media/{audio,book}/download` — routes that have never existed on any build | Dead constants and two uncalled methods | Removed. Only `image` and `video` have download routes |
| 6 | `ListAPI.goodsSearch` = `/api/v1/goods/search` — no such route (search is `GET /goods?search=`) | Unused constant | Removed |

`test/endpoint_backend_pin_test.dart` now pins both halves — every `ListAPI`
path against the registered routes, and every `(verb, path)` this package sends
against the verb that path is registered with. It reads `handler.go`, not a
hand-maintained list, and skips (with a message) when the backend clone is not
beside this one. Reintroducing any of #1, #2 or #6 fails it by name.

## Still broken — needs a backend commit and deploy

**USB printers cannot be saved, and printer ownership cannot be stored.**

The POS offers `connection_type: 'usb'` and sends `name` and
`owner_cash_register_id`. The deployed API:

* rejects an empty `ip` (`"ip is required"`) — the client already retries once
  with a `127.0.0.1:9100` placeholder for this;
* then rejects the retry too, with `"connection_type must be one of: cable,
  wlan"` — `isValidPrinterConnectionType` has no `usb` case. The client does
  **not** work around this one, and should not: storing a USB printer as
  `cable` at `127.0.0.1` would make every *other* terminal try to print to its
  own loopback;
* silently drops `name` and `owner_cash_register_id` — neither column exists
  (`printer_settings` last changed in tenant migration 40).

So the operator gets the local-only warning, the printer never reaches the
server, and cross-terminal relay has no ownership to route on.

The fix is already written, in the backend working tree, uncommitted:
`75_printer_settings_owner.up.sql`, the `usb`/`IsAddressless` connection type,
`name` + `branch_id` + `owner_cash_register_id` on all three printer models,
and `uq_printer_settings_identity_active`. It needs committing to
`feat/branch-shifts` (or whatever branch is deployed next) and deploying.
Nothing on the POS side can close this gap.

The same working tree also carries `price_per_hour` as `*float64`. That is no
longer load-bearing after fix #4, but it is the change that lets a table have a
fractional hourly rate.

## Checked and correct — worth not re-deriving

* **Sync.** `POST /sync/{pull,push}` bodies and the `{status,message,data,code}`
  envelope match. `CheckTerminalOrUserAuth` admits both token kinds.
* **Orders.** Create, add-items, pay, cancel, transfer, and all four
  table-timer routes match on path, verb, body and role. `client_item_id` is a
  real field on `CreateOrderItemInline` and is honoured.
* **Pay idempotency.** `client_payment_id` is *not* a field on
  `MarkOrderPaidRequest` — `encoding/json` drops it. What actually makes a
  replay safe is `MarkOrderPaid`'s own guard: an already-paid order is returned
  unchanged, 200, with no second `bill_payment`. The comment in
  `payment_repository_impl.dart` used to imply the server keyed on the id; it
  now says this.
* **Cash-register shifts.** Open/close/active all match, including the
  `cash_register_id` query parameter the active lookup requires.
* **Role gates.** Everything the POS calls under `RolesAdminOnly` —
  `PUT /branches/:id`, printer-settings writes, user CRUD — is reachable only
  from Settings, which `canAccessSettings` already limits to
  admin/manager/superadmin. No 403 is reachable from a cashier or waiter
  session.
  `GET /users/staff` is `RolesTerminalAndAdmin` and *would* 403 for a plain
  cashier, but nothing calls it: the waiter dropdown reads the replicated
  `users` table. The comments that claimed otherwise have been corrected.
* **`GET /branches/:id`** is likewise dead on the client —
  `MainRepositoryImpl.getServiceCharge` reads the replica.

## Out of scope but adjacent

The admin panel (`mary_front/frontv2`) has a live `/auth/sign-up` route whose
form posts to `/api/v1/auth/register` — the same 404 as fix #1. It is a
template leftover, not linked from anywhere, and reachable only by typing the
URL. Its user *create* and *update* paths (`POST /api/v1/users`, `PATCH
/api/v1/users/{id}`) are already correct.
