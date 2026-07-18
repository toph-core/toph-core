# media

4 endpoint(s)

[← Back to index](../README.md)

### `POST` `/api/v1/media/image`

**Rasm yuklash**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `file` | formData | file | yes | Rasm fayli |

**Responses**

- `200` — OK → `model.DownloadSuccessResponse`

---

### `POST` `/api/v1/media/image/download`

**Rasmni yuklab olish**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.DownloadRequest | yes | Rasm obyekt nomi |

**Body schema:** `model.DownloadRequest`

**Responses**

- `200` — Rasm fayli → `file`
- `404` — Rasm topilmadi → `model.ErrorResponse`

---

### `POST` `/api/v1/media/video`

**Video yuklash**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `file` | formData | file | yes | Video fayli |

**Responses**

- `200` — OK → `model.DownloadSuccessResponse`

---

### `POST` `/api/v1/media/video/download`

**Videoni yuklab olish**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.DownloadRequest | yes | Video obyekt nomi |

**Body schema:** `model.DownloadRequest`

**Responses**

- `200` — Video fayli → `file`

---

