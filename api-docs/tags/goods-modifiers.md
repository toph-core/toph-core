# goods-modifiers

3 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/goods/{id}/modifiers`

**Get modifiers by good ID**

Retrieve all modifiers attached to a good

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Good ID |

**Responses**

- `200` — OK → `array<model.GoodModifierResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/goods/{id}/modifiers`

**Attach modifier to good**

Attach a modifier to a good

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Good ID |
| `request` | body | model.AttachModifiersToGoodRequest | yes | Attach modifiers request |

**Body schema:** `model.AttachModifiersToGoodRequest`

**Responses**

- `201` — Created → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/goods/{id}/modifiers/{modifierId}`

**Detach modifier from good**

Detach a modifier from a good

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Good ID |
| `modifierId` | path | string | yes | Modifier ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

