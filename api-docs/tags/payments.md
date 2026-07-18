# payments

1 endpoint(s)

[← Back to index](../README.md)

### `POST` `/api/v1/payments/create`

**Create a new payment invoice**

Creates a new payment invoice for the authenticated user

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `Authorization` | header | string | yes | Bearer token |
| `request` | body | model.IndexCreation | yes | Invoice creation request |

**Body schema:** `model.IndexCreation`

**Responses**

- `200` — Successfully created invoice → `model.CreateInvoiceResponse`
- `400` — Invalid request or missing required fields → `model.CreateInvoiceResponse`
- `401` — Unauthorized - User not authenticated → `model.CreateInvoiceResponse`
- `500` — Internal server error → `model.CreateInvoiceResponse`

---

