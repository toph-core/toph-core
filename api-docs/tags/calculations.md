# Calculations

14 endpoint(s)

[← Back to index](../README.md)

### `POST` `/api/v1/calculations/preview`

**Preview calculations (no DB writes)**

Calculate ingredient + compound costs for UI preview. Does not create any DB records.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.PreviewCalculationsRequest | yes | Preview calculations request |

**Body schema:** `model.PreviewCalculationsRequest`

**Responses**

- `200` — Preview generated successfully → `model.PreviewCalculationsResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/compounds/calculations`

**Get calculations by compound ID**

Retrieve all calculations (ingredients and child compounds) for a specific compound

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `compound_id` | query | string | yes | Compound ID |

**Responses**

- `200` — List of calculations → `array<model.CalculationResponse>`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `POST` `/api/v1/compounds/calculations`

**Create compound calculation**

Add ingredient or child compound to a compound and create a calculation record

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `req` | body | model.CreateCompoundCalculationRequest | yes | Compound ID, ingredient ID or compound ID to add, and quantity |

**Body schema:** `model.CreateCompoundCalculationRequest`

**Responses**

- `201` — Created → `model.CalculationResponse`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `DELETE` `/api/v1/compounds/calculations/{id}`

**Delete calculation**

Delete a calculation record

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Calculation ID |

**Responses**

- `200` — OK → `object`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `404` — Not found → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `GET` `/api/v1/compounds/calculations/{id}`

**Get calculation by ID**

Retrieve a single calculation record by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Calculation ID |

**Responses**

- `200` — OK → `model.CalculationResponse`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `404` — Not found → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `PUT` `/api/v1/compounds/calculations/{id}`

**Update calculation quantity**

Update only the quantity of a calculation. Total cost is automatically recalculated as: total_cost = quantity × price_per_unit. To change ingredient/compound, delete and create a new calculation.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Calculation ID |
| `req` | body | model.UpdateCalculationRequest | yes | Update request (quantity only) |

**Body schema:** `model.UpdateCalculationRequest`

**Responses**

- `200` — OK → `model.CalculationResponse`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `404` — Not found → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `GET` `/api/v1/compounds/{id}/with-calculations`

**Get compound with calculations**

Retrieve a compound with all its calculations and profit information

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Compound ID |
| `expand` | query | string | no | Comma-separated list of fields to expand (e.g. ingredients,compounds) |

**Responses**

- `200` — OK → `model.CompoundCalculationResponse`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `404` — Not found → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `GET` `/api/v1/goods/calculations`

**Get calculations by good ID**

Retrieve all calculations (ingredients and compounds) for a specific good

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `good_id` | query | string | yes | Good ID |

**Responses**

- `200` — List of calculations → `array<model.CalculationResponse>`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `POST` `/api/v1/goods/calculations`

**Create good calculation**

Add ingredient or compound to a good and create a calculation record

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `req` | body | model.CreateGoodCalculationRequest | yes | Good ID, ingredient ID or compound ID to add, and quantity |

**Body schema:** `model.CreateGoodCalculationRequest`

**Responses**

- `201` — Created → `model.CalculationResponse`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `GET` `/api/v1/goods/calculations/history`

**Get good recipe at a point in time**

Returns all calculation rows that were active for a good at the given timestamp.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | query | string | yes | Good ID |
| `at` | query | string | no | RFC3339 timestamp (defaults to now) |

**Responses**

- `200` — Calculations at the given time → `array<model.CalculationResponse>`
- `400` — Bad request → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `DELETE` `/api/v1/goods/calculations/{id}`

**Delete calculation**

Delete a calculation record. Used by both /goods/calculations/{id} and /compounds/calculations/{id}

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Calculation ID |

**Responses**

- `200` — OK → `object`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `404` — Not found → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `GET` `/api/v1/goods/calculations/{id}`

**Get calculation by ID**

Retrieve a single calculation record by ID. Used by both /goods/calculations/{id} and /compounds/calculations/{id}

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Calculation ID |

**Responses**

- `200` — OK → `model.CalculationResponse`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `404` — Not found → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `PUT` `/api/v1/goods/calculations/{id}`

**Update calculation quantity (auto-recalculates total_cost)**

Update only the quantity of a calculation. Total cost is automatically recalculated as: total_cost = quantity × price_per_unit. To change ingredient/compound, delete and create a new calculation. Used by both /goods/calculations/{id} and /compounds/calculations/{id}

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Calculation ID |
| `req` | body | model.UpdateCalculationRequest | yes | Update request (quantity only) |

**Body schema:** `model.UpdateCalculationRequest`

**Responses**

- `200` — OK → `model.CalculationResponse`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `404` — Not found → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

### `GET` `/api/v1/goods/{id}/with-calculations`

**Get good with calculations**

Retrieve a good with all its ingredient calculations and profit information

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Good ID |
| `expand` | query | string | no | Comma-separated list of fields to expand (e.g. ingredients,compounds) |

**Responses**

- `200` — OK → `model.GoodCalculationResponse`
- `400` — Bad request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `404` — Not found → `model.ErrorData`
- `500` — Internal server error → `model.ErrorData`

---

