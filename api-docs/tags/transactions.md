# transactions

7 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/transactions`

**Get all transactions**

Retrieve all transactions with pagination, filters, search and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by comment or description |
| `type` | query | string | no | Filter by transaction type |
| `pay_type` | query | string | no | Filter by pay type (cash, card) |
| `cash_register_id` | query | string | no | Filter by cash register ID |
| `group_transaction_id` | query | string | no | Filter by group transaction ID |
| `date_from` | query | string | no | Start date (YYYY-MM-DD) |
| `date_to` | query | string | no | End date (YYYY-MM-DD) |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |

**Responses**

- `200` — OK → `model.PaginatedTransactionsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/transactions/income-expense`

**Create income or expense transaction**

Create a new income or expense transaction. Type must be "income" or "expense".

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateIncomeExpenseRequest | yes | Transaction data |

**Body schema:** `model.CreateIncomeExpenseRequest`

**Responses**

- `201` — Created → `model.TransactionResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/transactions/report`

**Cash register report**

Returns summary by transaction type, income/expense grouped by category, and day balance totals.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `from` | query | string | no | Start datetime (RFC3339) |
| `to` | query | string | no | End datetime (RFC3339) |
| `cash_register_id` | query | string | no | Filter by cash register UUID |

**Responses**

- `200` — OK → `model.CashReportResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/transactions/transfer`

**Transfer between cash registers**

Transfer an amount between two cash registers (optionally across branches)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateCashTransferRequest | yes | Transfer data |

**Body schema:** `model.CreateCashTransferRequest`

**Responses**

- `201` — Created → `model.TransactionResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/transactions/{id}`

**Delete transaction**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Transaction ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/transactions/{id}`

**Get transaction by ID**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Transaction ID |

**Responses**

- `200` — OK → `model.TransactionResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`

---

### `PUT` `/api/v1/transactions/{id}`

**Update transaction**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Transaction ID |
| `input` | body | model.UpdateTransactionRequest | yes | Update data |

**Body schema:** `model.UpdateTransactionRequest`

**Responses**

- `200` — OK → `model.TransactionResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

