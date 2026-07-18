# Sync

3 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/sync/change-logs`

**Get change logs**

Get change_log entries with filters

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `entity` | query | string | no | Entity name (table) |
| `action` | query | string | no | Action (create/update/delete) |
| `from_id` | query | integer | no | Start ID (inclusive) |
| `to_id` | query | integer | no | End ID (inclusive) |
| `from_time` | query | string | no | Start time (RFC3339) |
| `to_time` | query | string | no | End time (RFC3339) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `order` | query | string | no | asc or desc |

**Responses**

- `200` — OK → `model.ChangeLogListResponse`

---

### `POST` `/api/v1/sync/pull`

**Sync pull**

Get changes since last_sync_cursor

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.SyncPullRequest | yes | Sync pull request |

**Body schema:** `model.SyncPullRequest`

**Responses**

- `200` — OK → `model.SyncPullResponse`

---

### `POST` `/api/v1/sync/push`

**Sync push**

Apply changes from offline server

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.SyncPushRequest | yes | Sync push request |

**Body schema:** `model.SyncPushRequest`

**Responses**

- `200` — OK → `model.SyncPushResult`

---

