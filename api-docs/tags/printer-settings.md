# printer-settings

5 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/settings/printer-settings`

**List printer settings**

Get printer settings list for current tenant

_Auth: Bearer required_

**Responses**

- `200` — OK → `handler.PrinterSettingListSuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`

---

### `POST` `/api/v1/settings/printer-settings`

**Create printer setting**

Create new printer setting for current tenant

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreatePrinterSettingRequest | yes | Create printer setting request |

**Body schema:** `model.CreatePrinterSettingRequest`

**Responses**

- `201` — Created → `handler.PrinterSettingCreateSuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`

---

### `DELETE` `/api/v1/settings/printer-settings/{id}`

**Delete printer setting**

Soft delete printer setting by id for current tenant

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Printer setting ID |

**Responses**

- `200` — OK → `handler.PrinterSettingDeleteSuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`

---

### `GET` `/api/v1/settings/printer-settings/{id}`

**Get printer setting by id**

Get one printer setting by id for current tenant

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Printer setting ID |

**Responses**

- `200` — OK → `handler.PrinterSettingGetSuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`

---

### `PUT` `/api/v1/settings/printer-settings/{id}`

**Update printer setting**

Update printer setting by id for current tenant

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Printer setting ID |
| `request` | body | model.UpdatePrinterSettingRequest | yes | Update printer setting request |

**Body schema:** `model.UpdatePrinterSettingRequest`

**Responses**

- `200` — OK → `handler.PrinterSettingUpdateSuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`

---

