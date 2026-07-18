# SeparationActs

10 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/separation-acts`

**List separation acts**

List acts filtered by storage, group, ingredient, status, date range. Returns total count and sums.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `storage_id` | query | string | no | Filter by storage UUID |
| `group_id` | query | string | no | Filter by group UUID |
| `ingredient_id` | query | string | no | Filter by source ingredient UUID |
| `status` | query | string | no | Filter by status (draft/active/cancelled) |
| `start_date` | query | string | no | Start date (RFC3339) |
| `end_date` | query | string | no | End date (RFC3339) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `model.SeparationActListResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/separation-acts`

**Create separation act**

Create a new separation act in draft status. Add items, then confirm to apply stock changes.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateSeparationActRequest | yes | Create separation act |

**Body schema:** `model.CreateSeparationActRequest`

**Responses**

- `201` — Created → `model.SeparationActResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/separation-acts/batch`

**Create separation act with items (batch)**

Creates act header and upserts all output items in one request. Returns full act with stock preview.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateSeparationActBatchRequest | yes | Batch create |

**Body schema:** `model.CreateSeparationActBatchRequest`

**Responses**

- `201` — Created → `model.SeparationActWithItemsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/separation-acts/{id}`

**Delete separation act**

Soft-deletes a separation act. If confirmed (active), reverses all stock changes first.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Separation Act ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/separation-acts/{id}`

**Get separation act by ID**

Returns act header + all items with stock_before/stock_after

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Separation Act ID |

**Responses**

- `200` — OK → `model.SeparationActWithItemsResponse`
- `404` — Not Found → `model.ErrorResponse`

---

### `PUT` `/api/v1/separation-acts/{id}`

**Update separation act**

Update storage, group, date, description. Only works on draft acts.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Separation Act ID |
| `request` | body | model.UpdateSeparationActRequest | yes | Update act |

**Body schema:** `model.UpdateSeparationActRequest`

**Responses**

- `200` — OK → `model.SeparationActResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/separation-acts/{id}/cancel`

**Cancel separation act**

Cancels a draft act (no stock change)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Separation Act ID |

**Responses**

- `200` — OK → `model.SeparationActResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/separation-acts/{id}/confirm`

**Confirm separation act**

Confirms act: removes source ingredient qty from source storage, adds output items to their storages, saves stock snapshots.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Separation Act ID |

**Responses**

- `200` — OK → `model.SeparationActResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/separation-acts/{id}/items`

**Upsert separation act items**

Add/update multiple output ingredient items. Returns items with live stock preview.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Separation Act ID |
| `request` | body | model.UpsertSeparationActItemsRequest | yes | Items to upsert |

**Body schema:** `model.UpsertSeparationActItemsRequest`

**Responses**

- `200` — OK → `array<model.SeparationActItemResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/separation-acts/{id}/items/{item_id}`

**Delete separation act item**

Remove an output ingredient item from a draft act

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Separation Act ID |
| `item_id` | path | string | yes | Item ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

