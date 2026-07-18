# Order Items

13 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/order-items`

**Get all order items**

Get all order items with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.OrderItemResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/order-items`

**Create order items**

Create one or more order items for the same order. price can be omitted; it will be auto-filled from goods.price.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateOrderItemRequest | yes | Create order items request |

**Body schema:** `model.CreateOrderItemRequest`

**Responses**

- `201` — Created → `array<model.OrderItemResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/order-items/order/{orderId}`

**Get order items by order**

Get all order items for a given order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `orderId` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `array<model.OrderItemResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/order-items/status/{status}`

**Get order items by status**

Get order items filtered by status with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `status` | path | string | yes | Order item status |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.OrderItemResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/order-items/{id}`

**Delete order item**

Delete (soft delete) an order item

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order Item ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/order-items/{id}`

**Get order item by ID**

Get a single order item by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order Item ID |

**Responses**

- `200` — OK → `model.OrderItemDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/order-items/{id}`

**Update order item**

Update an existing order item

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order Item ID |
| `request` | body | model.UpdateOrderItemRequest | yes | Update order item request |

**Body schema:** `model.UpdateOrderItemRequest`

**Responses**

- `200` — OK → `model.OrderItemResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/order-items/{id}/cancel`

**Cancel order item**

Cancel an order item

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order Item ID |

**Responses**

- `200` — OK → `model.OrderItemResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/order-items/{id}/cooking`

**Mark order item cooking**

Mark an order item as cooking

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order Item ID |

**Responses**

- `200` — OK → `model.OrderItemResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/order-items/{id}/quantity`

**Update order item quantity**

Update the quantity of an order item

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order Item ID |
| `request` | body | model.UpdateOrderItemQuantityRequest | yes | Update order item quantity request |

**Body schema:** `model.UpdateOrderItemQuantityRequest`

**Responses**

- `200` — OK → `model.OrderItemResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/order-items/{id}/ready`

**Mark order item ready**

Mark an order item as ready

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order Item ID |

**Responses**

- `200` — OK → `model.OrderItemResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/order-items/{id}/restore`

**Restore order item**

Restore a soft-deleted order item

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order Item ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/order-items/{id}/status`

**Update order item status**

Update the status of an order item

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order Item ID |
| `request` | body | model.UpdateOrderItemStatusRequest | yes | Update order item status request |

**Body schema:** `model.UpdateOrderItemStatusRequest`

**Responses**

- `200` — OK → `model.OrderItemResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

