# deductions

16 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/deductions`

**Get deductions**

Retrieve deductions with filters and pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `date_from` | query | string | no | Filter from date (YYYY-MM-DD) |
| `date_to` | query | string | no | Filter to date (YYYY-MM-DD) |
| `status` | query | string | no | Filter by status (draft, active) |
| `storage_id` | query | string | no | Filter by storage UUID |
| `act_group_id` | query | string | no | Filter by act group UUID |
| `ingredient_id` | query | string | no | Filter by ingredient UUID (matches deduction items) |
| `expand` | query | string | no | Comma-separated relations to expand (e.g. storage_id) |

**Responses**

- `200` — Deductions → `model.PaginatedDeductionsResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/deductions`

**Create deduction**

Create a new deduction with items, expand into ingredient usage, subtract from stock and compute balance

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateDeductionRequest | yes | Deduction create data |

**Body schema:** `model.CreateDeductionRequest`

**Responses**

- `201` — Created → `model.DeductionResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/deductions/batch`

**Batch delete deductions**

Soft-delete multiple deductions; if active, stock is reversed for each

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.DeleteDeductionsBatchRequest | yes | IDs to delete |

**Body schema:** `model.DeleteDeductionsBatchRequest`

**Responses**

- `200` — Deleted → `model.SuccessResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/deductions/group`

**Get deduction act groups**

Retrieve deduction act groups with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |

**Responses**

- `200` — Deduction act groups → `array<model.DeductionActGroupResponse>`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/deductions/group`

**Create deduction act group**

Create a new deduction act group

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateDeductionActGroupRequest | yes | Deduction act group data |

**Body schema:** `model.CreateDeductionActGroupRequest`

**Responses**

- `201` — Deduction act group created → `model.DeductionActGroupResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/deductions/group/{id}`

**Delete deduction act group**

Soft delete a deduction act group

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction Act Group ID |

**Responses**

- `200` — Deleted → `model.SuccessResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/deductions/group/{id}`

**Get deduction act group by ID**

Retrieve a specific deduction act group by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction Act Group ID |

**Responses**

- `200` — Deduction act group details → `model.DeductionActGroupResponse`
- `400` — Invalid ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/deductions/group/{id}`

**Update deduction act group**

Update an existing deduction act group's information

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction Act Group ID |
| `input` | body | model.UpdateDeductionActGroupRequest | yes | Deduction act group update data |

**Body schema:** `model.UpdateDeductionActGroupRequest`

**Responses**

- `200` — Updated → `model.DeductionActGroupResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/deductions/group/{id}/restore`

**Restore deduction act group**

Restore a previously deleted deduction act group

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction Act Group ID |

**Responses**

- `200` — Restored → `model.DeductionActGroupResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/deductions/{id}`

**Delete deduction**

Soft delete a deduction

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction ID |

**Responses**

- `200` — Deleted → `model.SuccessResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/deductions/{id}`

**Get deduction by ID**

Retrieve a deduction with items and ingredient breakdown

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction ID |
| `expand` | query | string | no | Comma-separated relations to expand (e.g. storage_id) |

**Responses**

- `200` — Deduction → `model.DeductionResponse`
- `400` — Invalid ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/deductions/{id}`

**Update deduction**

Update deduction fields (date, group, storage, descriptions, status). Items are not changed.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction ID |
| `input` | body | model.UpdateDeductionRequest | yes | Deduction update data |

**Body schema:** `model.UpdateDeductionRequest`

**Responses**

- `200` — Updated → `model.DeductionResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/deductions/{id}/items/batch`

**Batch delete deduction items**

Remove multiple items from a deduction; if active, stock is reversed for each

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction ID |
| `input` | body | model.DeleteDeductionItemsBatchRequest | yes | Item IDs to delete |

**Body schema:** `model.DeleteDeductionItemsBatchRequest`

**Responses**

- `200` — Updated deduction → `model.DeductionResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/deductions/{id}/items/batch`

**Batch update deduction items**

Full replace of deduction items. Optionally update deduction fields (date, status, storage_id, etc.) in the same call. Stock adjusted on status transition.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction ID |
| `input` | body | model.UpsertDeductionItemsRequest | yes | Deduction items (required) + optional deduction fields |

**Body schema:** `model.UpsertDeductionItemsRequest`

**Responses**

- `200` — Updated deduction with new items → `model.DeductionResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `404` — Deduction not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/deductions/{id}/items/{itemId}`

**Delete deduction item**

Removes a single item from a deduction and adds its deducted quantities back to stock

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction ID |
| `itemId` | path | string | yes | Deduction Item ID |

**Responses**

- `200` — Updated deduction → `model.DeductionResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `404` — Not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/deductions/{id}/restore`

**Restore deduction**

Restore a previously deleted deduction

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Deduction ID |

**Responses**

- `200` — Restored → `model.DeductionResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

