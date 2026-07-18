# Metadata

1 endpoint(s)

[← Back to index](../README.md)

### `GET` `/metadata`

**Get bulk metadata for dropdown options**

Retrieves field data for multiple entity types. Each entity can optionally specify fields: menus(id,name,description). Defaults to {id,name}.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `include` | query | string | no | Comma-separated entity names with optional field list, e.g. menus(id,name,description),halls,departments(id,name,color_code) |

**Responses**

- `200` — OK → `object`
- `400` — Invalid entity in whitelist → `model.ErrorData`
- `500` — Database error → `model.ErrorData`

---

