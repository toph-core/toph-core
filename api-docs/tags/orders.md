# Orders

24 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/orders`

**Get all orders**

Get all orders with type, status, period/from-to, table filters and created/updated date sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `type` | query | string | no | Order type |
| `status` | query | string | no | Order status |
| `from` | query | string | no | Start date (YYYY-MM-DD) |
| `to` | query | string | no | End date (YYYY-MM-DD) |
| `table_id` | query | string | no | Table ID |
| `sort_by` | query | string | no | Sort field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.OrderResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders`

**Create order**

Create a new order. You can optionally create multiple order items in the same request via the items array. total_amount is computed server-side from items and service/discount fields.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateOrderRequest | yes | Create order request |

**Body schema:** `model.CreateOrderRequest`

**Responses**

- `201` — Created → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/batch`

**Create orders batch**

Create multiple orders in one request. Useful for offline sync.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateOrderBatchRequest | yes | Create orders batch request |

**Body schema:** `model.CreateOrderBatchRequest`

**Responses**

- `201` — Created → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/orders/my`

**Get my orders**

Get current authenticated waiter's own orders with optional filters

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `scope` | query | string | no | Scope filter: active, reservations, history, all |
| `order_type` | query | string | no | Order type filter: dine_in, takeaway |
| `table_id` | query | string | no | Table ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `model.WaiterOrderListResponse`
- `400` — Bad Request → `model.ErrorData`
- `401` — Unauthorized → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `GET` `/api/v1/orders/status/{status}`

**Get orders by status**

Get orders filtered by status with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `status` | path | string | yes | Order status |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.OrderResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/orders/table/{tableId}`

**Get orders by table**

Get orders filtered by table ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `tableId` | path | string | yes | Table ID |

**Responses**

- `200` — OK → `array<model.OrderResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/orders/waiter/{waiterId}`

**Get orders by waiter**

Get orders filtered by waiter ID with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `waiterId` | path | string | yes | Waiter ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.OrderResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/orders/{id}`

**Delete order**

Delete (soft delete) an order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/orders/{id}`

**Get order by ID**

Get a single order by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/orders/{id}`

**Update order**

Update an existing order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |
| `request` | body | model.UpdateOrderRequest | yes | Update order request |

**Body schema:** `model.UpdateOrderRequest`

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/activate`

**Activate reserved order**

Manually activate a reserved or rescheduled order (sets status to open)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/assign-cashier/{cashierId}`

**Assign cashier to order**

Assign a cashier to an order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |
| `cashierId` | path | string | yes | Cashier ID |

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/assign-waiter/{waiterId}`

**Assign waiter to order**

Assign a waiter to an order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |
| `waiterId` | path | string | yes | Waiter ID |

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/cancel`

**Cancel order**

Cancel an order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/cooking`

**Mark order cooking**

Mark an order as cooking

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/items`

**Add order items**

Append multiple order items to an existing order (e.g. dessert after meal). Item price is auto-filled from goods.price and order totals are recalculated server-side.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |
| `request` | body | model.AddOrderItemsRequest | yes | Add order items request |

**Body schema:** `model.AddOrderItemsRequest`

**Responses**

- `200` — OK → `model.AddOrderItemsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/pay`

**Mark order paid**

Mark an order as paid

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |
| `request` | body | model.MarkOrderPaidRequest | yes | Mark order paid request |

**Body schema:** `model.MarkOrderPaidRequest`

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/ready`

**Mark order ready**

Mark an order as ready

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/reschedule`

**Reschedule order**

Move a reservation to a new scheduled time with an optional comment

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |
| `body` | body | model.RescheduleOrderRequest | yes | Reschedule request |

**Body schema:** `model.RescheduleOrderRequest`

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/restore`

**Restore order**

Restore a soft-deleted order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/served`

**Mark order served**

Mark an order as served

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/orders/{id}/status`

**Update order status**

Update status of an existing order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Order ID |
| `request` | body | model.UpdateOrderStatusRequest | yes | Update order status request |

**Body schema:** `model.UpdateOrderStatusRequest`

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/orders/{id}/table-price`

**Get table price for order**

Calculates price based on table's price_per_hour and time elapsed. Uses scheduled_at if set, otherwise created_at. Returns error if table has no hourly price.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `model.TablePriceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/transfer`

**Transfer order to different table**

Transfer an order from its current table to a target table

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Order ID |
| `request` | body | model.OrderTransferRequest | yes | Transfer request with target_table_id |

**Body schema:** `model.OrderTransferRequest`

**Responses**

- `200` — OK → `model.OrderResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `409` — Conflict → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

