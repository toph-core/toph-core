# Transfers

9 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/transfers`

**Get all transfers**

Get transfers visible to the current branch, with optional filters

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Pass 'items' to include transfer items in each result |
| `date_from` | query | string | no | Filter by created_at, from date (YYYY-MM-DD or RFC3339) |
| `date_to` | query | string | no | Filter by created_at, to date (YYYY-MM-DD or RFC3339) |
| `status` | query | string | no | Filter by status (draft/active/deleted) |
| `from_branch_id` | query | string | no | Filter by sender branch ID |
| `to_branch_id` | query | string | no | Filter by receiver branch ID |
| `from_storage_id` | query | string | no | Filter by sender storage ID |
| `to_storage_id` | query | string | no | Filter by receiver storage ID |
| `act_group_id` | query | string | no | Filter by act group ID |
| `ingredient_id` | query | string | no | Filter by ingredient ID |

**Responses**

- `200` — OK → `model.PaginatedTransfersResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/transfers`

**Create transfer (header only)**

Create a transfer without items. Items can be added later.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateTransferRequest | yes | Transfer request |

**Body schema:** `model.CreateTransferRequest`

**Responses**

- `201` — Created → `model.TransferResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/transfers/batch`

**Batch delete transfers**

Soft delete multiple transfers and reverse all their stock changes

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.DeleteTransfersBatchRequest | yes | Transfer IDs to delete |

**Body schema:** `model.DeleteTransfersBatchRequest`

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/transfers/batch`

**Create transfer with items (batch)**

Create a transfer and its items in one call. Stock is moved immediately.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateTransferBatchRequest | yes | Transfer batch request |

**Body schema:** `model.CreateTransferBatchRequest`

**Responses**

- `201` — Created → `model.TransferResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/transfers/items`

**Add items to transfer**

Add items to an existing active transfer. Stock is moved immediately.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateTransferItemsRequest | yes | Transfer items request |

**Body schema:** `model.CreateTransferItemsRequest`

**Responses**

- `201` — Created → `model.TransferResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/transfers/items/{id}`

**Delete transfer item**

Delete a single transfer item and reverse its stock change

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Transfer Item ID |

**Responses**

- `204` — Transfer item deleted successfully
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/transfers/{id}`

**Delete transfer**

Soft delete a transfer and reverse all stock changes

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Transfer ID |

**Responses**

- `204` — Transfer deleted successfully
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/transfers/{id}`

**Get transfer by ID**

Get a transfer with all its items

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Transfer ID |

**Responses**

- `200` — OK → `model.TransferResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`

---

### `PUT` `/api/v1/transfers/{id}/items/batch`

**Batch update transfer items**

Replaces all transfer items. Old stock changes are reversed, then new quantities are applied.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Transfer ID |
| `input` | body | model.UpsertTransferItemsRequest | yes | New transfer items |

**Body schema:** `model.UpsertTransferItemsRequest`

**Responses**

- `200` — Updated transfer with new items → `model.TransferResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

