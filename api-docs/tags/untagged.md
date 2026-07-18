# untagged

1 endpoint(s)

[← Back to index](../README.md)

### `PUT` `/api/v1/goods/{id}/with-calculations`

**Update good with calculations and modifiers (One Save)**

Update a good/menu item and replace all its ingredient calculations, compound calculations, and modifiers in one atomic transaction.

**How it works:**
- Update the good first
- Delete all existing calculations for this good
- Create the new ingredient calculations (price from invoice_detail)
- Create the new compound calculations (price from compound.price)
- Replace all good modifiers and create their ingredient/compound calculations
- If any step fails, everything is rolled back

**Modifier calculations example:**
"modifiers": [
{ "modifier_id": "uuid", "is_required": false, "sort_order": 1,
"ingredient_calculations": [{"ingredient_id": "uuid", "quantity": "2.5", "price": "1500.00"}],
"compound_calculations": [{"compound_id": "uuid", "quantity": "1"}] }
]

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.UpdateGoodWithCalculationsRequest | yes | Good update + ingredient calculations + compound calculations + modifiers |

**Body schema:** `model.UpdateGoodWithCalculationsRequest`

**Responses**

- `200` — Good and all calculations updated successfully → `model.GoodWithCalculationsResponse`
- `400` — Invalid request (missing fields, invalid UUIDs, etc.) → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal error (ingredient not found, no invoice for ingredient, etc.) → `model.ErrorResponse`

---

