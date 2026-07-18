# group-transactions

6 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/group-transactions`

**Get all group transactions**

Retrieve all group transactions with pagination, optional search and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by group transaction name |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `model.PaginatedGroupTransactionsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/group-transactions`

**Create group transaction**

Create a new group transaction

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateGroupTransactionRequest | yes | Create group transaction request |

**Body schema:** `model.CreateGroupTransactionRequest`

**Responses**

- `201` — Created → `model.GroupTransactionResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/group-transactions/{id}`

**Delete group transaction**

Soft delete a group transaction by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Group Transaction ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/group-transactions/{id}`

**Get group transaction by ID**

Retrieve a group transaction by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Group Transaction ID |

**Responses**

- `200` — OK → `model.GroupTransactionResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/group-transactions/{id}`

**Update group transaction**

Update a group transaction by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Group Transaction ID |
| `request` | body | model.UpdateGroupTransactionRequest | yes | Update group transaction request |

**Body schema:** `model.UpdateGroupTransactionRequest`

**Responses**

- `200` — OK → `model.GroupTransactionResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/group-transactions/{id}/restore`

**Restore group transaction**

Restore a previously deleted group transaction

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Group Transaction ID |

**Responses**

- `200` — OK → `model.GroupTransactionResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

