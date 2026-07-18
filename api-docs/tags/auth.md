# auth

7 endpoint(s)

[← Back to index](../README.md)

### `POST` `/api/v1/auth/global/login`

**Global superadmin login**

Authenticate global superadmin (main DB) and return access and refresh tokens

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.GlobalLoginRequest | yes | Login credentials |

**Body schema:** `model.GlobalLoginRequest`

**Responses**

- `200` — Successfully logged in → `model.LoginResponse`
- `400` — Invalid request format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

### `POST` `/api/v1/auth/login`

**User login**

Authenticate user using username, password, and brand_id (slug) and return access token

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.LoginRequest | yes | Login credentials |

**Body schema:** `model.LoginRequest`

**Responses**

- `200` — Successfully logged in → `model.LoginResponse`
- `400` — Invalid request format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

### `POST` `/api/v1/auth/login-pincode`

**POS staff login with pincode**

Authenticate POS staff using brand_id, a role password (superadmin/admin/manager), and pincode

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.PincodeLoginRequest | yes | POS login credentials |

**Body schema:** `model.PincodeLoginRequest`

**Responses**

- `200` — Successfully logged in → `model.LoginResponse`
- `400` — Invalid request format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

### `POST` `/api/v1/auth/refresh`

**Token refresh**

Refresh access token using refresh token

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.RefreshRequest | yes | Refresh token |

**Body schema:** `model.RefreshRequest`

**Responses**

- `200` — Token refreshed successfully → `model.RefreshResponse`
- `400` — Invalid request format → `model.ErrorResponse`
- `401` — Invalid or expired refresh token → `model.ErrorResponse`

---

### `POST` `/api/v1/auth/register`

**Register a new user account**

Register a new user. User role defaults to 'user' if not provided.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.RegisterRequest | yes | User registration data |

**Body schema:** `model.RegisterRequest`

**Responses**

- `201` — User successfully registered → `model.RegisterResponse`
- `400` — Bad request - invalid input, missing required fields, or user already exists with phone number → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/auth/terminal/branches`

**Get branches for terminal**

Verify brand admin password and return list of branches

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | handler.getTerminalBranchesRequest | yes | Brand credentials |

**Body schema:** `handler.getTerminalBranchesRequest`

**Responses**

- `200` — OK → `array<model.BranchResponse>`

---

### `POST` `/api/v1/auth/terminal/token`

**Generate terminal token**

Verify brand admin password + branch_id and issue a permanent terminal JWT

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | handler.generateTerminalTokenRequest | yes | Terminal token request |

**Body schema:** `handler.generateTerminalTokenRequest`

**Responses**

- `200` — OK → `handler.generateTerminalTokenResponse`

---

