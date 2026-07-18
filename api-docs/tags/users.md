# users

13 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/user/me`

**Get current user profile**

Get the profile of the currently authenticated user

_Auth: Bearer required_

**Responses**

- `200` — User profile retrieved successfully → `model.UserResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — User not found → `model.ErrorResponse`

---

### `PUT` `/api/v1/user/password-update`

**Update user password**

Update the password of the currently authenticated user

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.UpdatePasswordRequest | yes | Password update data |

**Body schema:** `model.UpdatePasswordRequest`

**Responses**

- `200` — Password updated successfully → `model.SuccessResponse`
- `400` — Invalid request format or user ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Failed to update password → `model.ErrorResponse`

---

### `PUT` `/api/v1/user/update`

**Update current user profile**

Update the profile information of the currently authenticated user

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.UpdateUserRequest | yes | User update data |

**Body schema:** `model.UpdateUserRequest`

**Responses**

- `200` — User profile updated successfully → `model.UserResponse`
- `400` — Invalid request format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Failed to update user → `model.ErrorResponse`

---

### `GET` `/api/v1/users`

**Get users**

Get users with query, role, staff and branch_id filters

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `query` | query | string | no | Search by full_name, username, phone_number |
| `role` | query | string | no | Role filter |
| `staff` | query | boolean | no | Only staff users (exclude admin and superadmin) |
| `branch_id` | query | string | no | Branch ID filter (superadmin only) |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |

**Responses**

- `200` — OK → `array<model.UserResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `403` — Forbidden → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/users`

**Create a staff user**

Create a new staff user (admin, manager, cashier, waiter, kitchen). Requires admin role.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateStaffRequest | yes | Staff user data |

**Body schema:** `model.CreateStaffRequest`

**Responses**

- `201` — Staff user created → `model.UserResponse`
- `400` — Invalid input → `model.ErrorResponse`
- `403` — Forbidden → `model.ErrorResponse`

---

### `GET` `/api/v1/users/by-role`

**Get users by role**

Retrieve all users with a specific role with pagination and optional expand

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `role` | query | string | yes | User role (admin, manager, cashier, waiter, kitchen, user, superadmin) |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `expand` | query | string | no | Expand related fields (e.g. shift,branch) |

**Responses**

- `200` — Paginated list of users → `array<model.UserResponse>`
- `400` — Invalid role parameter → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/users/ratings`

**Get user ratings**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `period` | query | string | no | Period: weekly|monthly|all_time (default: monthly) |

**Responses**

- `200` — OK → `model.EmployeeRatingSwaggerResponse`
- `500` — Internal Server Error → `model.ErrorData`

---

### `GET` `/api/v1/users/search`

**Search users**

Search users by name, phone, or username with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `query` | query | string | yes | Search query (name, phone, or username) |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |

**Responses**

- `200` — List of matching users → `array<model.UserResponse>`
- `400` — Invalid query parameter → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/users/staff`

**Get staff users**

Retrieve all staff members (excluding admin/superadmin) with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `expand` | query | string | no | Expand related fields (e.g. shift,branch) |

**Responses**

- `200` — Paginated list of staff → `array<model.UserResponse>`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/users/{id}`

**Delete user**

Soft delete a user (mark as deleted without removing from database)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | User ID |

**Responses**

- `200` — User deleted successfully → `model.SuccessResponse`
- `400` — Invalid user ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/users/{id}`

**Get user by ID**

Retrieve a single user by their UUID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | User ID |

**Responses**

- `200` — OK → `model.UserResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/users/{id}`

**Update user profile by ID**

Update the profile information for the specified user (admin/superadmin use)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | User ID |
| `request` | body | model.UpdateUserRequest | yes | User update data |

**Body schema:** `model.UpdateUserRequest`

**Responses**

- `200` — User profile updated successfully → `model.UserResponse`
- `400` — Invalid request format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Failed to update user → `model.ErrorResponse`

---

### `POST` `/api/v1/users/{id}/restore`

**Restore user**

Restore a previously deleted user

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | User ID |

**Responses**

- `200` — User restored successfully → `model.SuccessResponse`
- `400` — Invalid user ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

