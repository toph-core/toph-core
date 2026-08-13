# Decision log — offline-first migration

Forks hit while executing `OFFLINE_FIRST_EVERYWHERE_PLAN.md`, what was chosen,
and what would change the answer. Newest last.

Entries exist for decisions where a reasonable engineer could have gone the
other way. Mechanical work is not logged.

---

## D1 — Creates queue instead of appearing (Phase 4, staff screen)

**Fork.** `POST /auth/register` and the hall/table create endpoints assign ids
server-side. A local row needs an id.

**Chosen.** Creates enqueue with no local row; the screen says so. Updates and
deletes apply locally and immediately.

**Why.** A client-invented id becomes a second identity for one row: replication
later delivers the server's version under the real id, and the invented one sits
beside it forever, undeletable because no server row matches it. A visible
"queued" state is worse UX than an instant one and better than a permanent ghost.

**Cost.** Asymmetric behaviour across every migrated screen. On a floor plan
("add table, nothing appears") it is a real papercut.

**What changes it.** Either the backend accepts client-supplied ids on those
endpoints (plan §5.4, cheap), or the outbox learns to reconcile a provisional id
against the one the create response returns. The first is preferable; the second
is entirely client-side if the first is refused. Screen code is unaffected either
way — the choice lives in the repository and drainer, so revisiting is cheap.

**Status.** **Closed** — by the client route, after checking the first. The
swagger spec confirms none of the create endpoints accept an `id`:
`RegisterRequest`, `CreateHallRequest`, `CreateCafeTableRequest`,
`CreateCategoryRequest`, `CreateGoodRequest` and `CreateTranslationRequest` all
omit it. So the backend option did not exist to take.

Creates now write a row under a provisional id, marked as such, and the drainer
swaps it for the server's when the response arrives — deleting the stand-in,
applying the real row, and rewriting every *pending* outbox reference to the old
id. `LocalWriteResult` is gone with the asymmetry it described.

A backend that accepted client ids would still be better: it would delete this
machinery rather than justify it. But it is no longer blocking anything.

---

## D2 — A 409 on a queued write is quarantined, not retried or dropped

**Fork.** The outbox must classify every failure as retry, permanent, or success.
409 fits none cleanly.

**Chosen.** Quarantine.

**Why.** It is genuinely ambiguous — "your earlier attempt already landed" and
"that username is taken" arrive identically. Retrying forever spams; dropping
loses a write. Quarantine routes it to the only thing that can tell the
difference: a person with the payload in front of them.

---

## D3 — Table occupancy is local authority, stored beside the replica

**Fork.** Occupancy is decided locally (a cashier opening an order, a peer's LAN
broadcast) but `cafe_tables.status` is a replicated, server-owned column.

**Chosen.** A separate `_table_status` table, overlaid on every `cafe_tables`
read.

**Why.** Chasing this found a live bug: `updateTableStatus` patched `status`
inside the cached row, and the reference-data hydration replaced that row
wholesale with the server's. Every TTL expiry reset the venue's occupancy to
whatever the server last knew — nothing, when offline. A busy table silently went
free. Keeping the two kinds of truth in one row means one always clobbers the
other; the only question is which, and when.

**Cost.** Reads pay an overlay. Stale rows need pruning (done on pull).

---

## D4 — Phase 5 detects feed gaps instead of deleting the follower's uplink

**Fork.** The plan says delete the follower's cloud uplink outright.

**Chosen.** Delete the *periodic* pull. Keep the uplink as gap recovery only.

**Why.** Applying a broadcast advances the cursor to its `next_sync_cursor`. A
follower that missed batches would carry its cursor over rows it never saw, and
nothing would request them again — it would look caught up while missing
arbitrary rows, with no later symptom pointing at it. The leader cannot serve the
recovery: it keeps current rows, not history, so it has no change log to replay.

**Cost.** A follower with no uplink *and* a gap stays behind until it gets one.

**What changes it.** A leader-side backfill would need the leader to retain
change history, which is a bigger feature than this phase.

---

## D5 — `setEnabled` survives Phase 6; the settings toggle does not

**Fork.** The plan says delete both when election goes default-on.

**Chosen.** Kill switch stays as an API. Operator-facing toggle removed.

**Why.** The canary the design doc asked for was a live multi-terminal venue.
What it got is `test/leader_takeover_test.dart` — a narrower guarantee, with
congested and partitioned real networks still unproven. Removing the only way to
disable this without a rebuild is not worth three lines. But whether the venue
elects a leader is not a decision to make mid-shift from a cashier screen.

**What changes it.** A real multi-terminal canary. Then delete it.

---

## D6 — The cluster card keeps its diagnostics, loses its role label

**Fork.** Plan says remove cluster role and leader identity from the sync-status
screen.

**Chosen.** Card stays, retitled, showing connectivity only — not Hub/Client.

**Why.** The role is now elected and transient; showing it invited reasoning
about something the operator neither controls nor should. But a follower that has
silently lost its leader otherwise looks identical to a healthy terminal, and
that is worth being able to see.

---

## D7 — The image cache is a seam, not a repository method

**Fork.** `imageStream` could have lived directly in `MenuRepositoryImpl`.

**Chosen.** Extracted to `core/media/local_image_cache.dart`, wired through plain
functions.

**Why.** It has enough logic to deserve testing — dedupe, failure settling, no
retry-per-rebuild — and its two collaborators are a process-wide singleton with
no seam and a Hive facade. Naming either as a type drags both into every test.

**Note.** This was where "no `FutureBuilder`" stopped looking like a style rule:
the two call sites had each made their own caching decisions, and differed. One
persisted bytes, one did not, so a widget used on four screens had no offline
images at all.

---

## D8 — The menu screens are not modifier-blocked

**Fork.** I had twice reported the menu screens as partially blocked on
`modifiers` / `goods_modifiers`, and offered to migrate them degraded.

**Chosen.** Migrate them fully. There is no tradeoff to make.

**Why.** Neither screen references modifiers — zero matches in 4,433 lines. The
plan's note that missing `modifiers` blocks "the order screen" is about the order
screen; I carried it to these two by association with the word "menu". Everything
they actually read — `goods`, `calculation`, `ingredients`, `categories`,
`translations` — replicates today.

**Correction.** I asked for a decision that did not need making. Checked before
building this time, which is what surfaced it.

---

## D9 — The goods total counts rows the page cannot decode

**Fork.** `GoodsModel` declares six fields non-nullable, and the repository
skips rows that fail to decode. The paginator's total is a `COUNT(*)`, which
does not decode — so a page can show fewer items than the total implies.

**Chosen.** Leave the disagreement, and test for it.

**Why.** Making them agree means decoding every matching row on every page —
the full-table cost the paginator exists to avoid. And the mismatch is the
honest signal: it says a menu item exists that this client cannot render.
Quietly lowering the count would hide that.

**Found by.** A test fixture too thin to decode, which produced an empty list
beside a correct-looking total — exactly what a real replica row missing a
column would do.

---

## D10 — Menu screens read categories from the replica, not `MenuRepository`

**Fork.** The meals screen already had a reactive category list over the Hive
store. Migrating only goods would have left it injecting `MenuRepository`.

**Chosen.** Categories move to the replica for these screens; `MenuRepository`
keeps serving everything else from Hive until its own screens follow.

**Why.** Same rule this migration has followed throughout: a screen whose writes
land in the replica must read the replica, or it cannot see its own edits. It
also removes the last repository injection from the screen, which is what the
§7 ratchet is actually measuring.

---

## D11 — A new translation blocks the save; an existing one does not

**Fork.** `good.name_i18n` is a *reference* to a translation row's id, and
`/translations` assigns that id server-side.

**Chosen.** Editing an existing meal's translations applies locally and works
offline. Creating the first ones refuses with a message.

**Why.** Queueing the translation would leave the good referencing nothing, so
the meal would save with its translations silently dropped — data loss dressed
as success. This is D1 again, in a harder form: the id is load-bearing for a
*second* row, so the usual "queue it and wait" does not degrade gracefully.

**Cost.** A brand-new meal with translations needs a connection. It needed one
before too, so this is not a regression — only a clearer failure.

**What changes it.** ~~The outbox would need to rewrite a queued payload once a
dependency's real id arrived.~~ **Done** — that is exactly what
`OutboxStore.rewriteReferences` does, so a meal can reference a translation that
has not been created yet. The editor's refusal is removed.

---

## D12 — Queued writes carry their request scope in the payload

**Fork.** `saveGoodWithCalculations` was called with `X-Brand-Id` /
`X-Branch-ID` headers built from the logged-in user. Sending happens later now.

**Chosen.** Capture the headers at enqueue time under a reserved payload key,
stripped by the handler before the body is sent.

**Why.** The drain can happen after a shift change. A write belongs to the scope
of whoever made it, not whoever is logged in when the network returns. Resolving
the headers at send time would silently reassign authorship.

**Alternative rejected.** A metadata column on `OutboxOperation` — a schema
change for one caller, where a reserved key does the job. Revisit if a second
write needs different context.

**Nearly missed.** `_scopeHeaders` showed up as an unused-element warning after
the rewire. Treating that as dead code would have dropped the headers silently.

---

## D13 — References are rewritten by whole-value match, pending ops only

**Fork.** When a provisional id becomes real, anything queued that referenced it
has to be repointed. How much to touch?

**Chosen.** Whole string values, recursively, in `pending` operations only.

**Why.** A substring replace would corrupt a description that merely quoted an
id — ids are UUIDs and appear in free text. And an operation already sent cannot
be amended, while a quarantined one is waiting on a human who needs to see what
was actually attempted, not a tidied version of it.

**Cost.** An operation that referenced a provisional id and was quarantined
before the create landed keeps a stale reference. It is visible in quarantine,
which is the right place for it.

---

## D14 — `password` joins the users redaction list

**Found by.** Switching staff creates to write a local row. The create body is
both the request and the row, and `redactKeys` covered `hash_password` and
`pincode` but not `password` — so the plaintext credential from the create form
would have landed in a table every staff screen can query.

**Chosen.** Redact it. The row keeps everything else.

**Still open.** The credential travels in the outbox payload, because a create
queued offline has to carry it to send later. That is narrower than a column in
`users` — one row, drained and deleted — but it is not nothing, and offline
staff creation deserves a second look before it reaches a venue.
