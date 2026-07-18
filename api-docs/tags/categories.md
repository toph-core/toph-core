# categories

12 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/categories`

**Get all categories**

Retrieve all categories with pagination, optional search, filters and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by category name |
| `department_id` | query | string | no | Filter by department ID |
| `storage_id` | query | string | no | Filter by storage ID |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedCategoriesResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/categories`

**Create a new category**

Create a new category with name and optional relationships (department, storage, parent)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateCategoryRequest | yes | Category creation data |

**Body schema:** `model.CreateCategoryRequest`

**Responses**

- `201` — Category created successfully → `model.CategoryResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/categories-lang`

**Get all categories with language support**

Retrieve all categories with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by category name |
| `department_id` | query | string | no | Filter by department ID |
| `storage_id` | query | string | no | Filter by storage ID |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedCategoriesResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/categories-lang/{id}`

**Get category by ID with language support**

Retrieve a specific category by its ID with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Category ID |
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |

**Responses**

- `200` — Category details → `model.CategoryResponse`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Category not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/categories/department/{departmentId}`

**Get categories by department**

Retrieve all categories for a specific department

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `departmentId` | path | string | yes | Department ID |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Categories found → `array<model.CategoryResponse>`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/categories/parent/{parentId}`

**Get subcategories by parent**

Retrieve all subcategories for a specific parent category

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `parentId` | path | string | yes | Parent Category ID |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Subcategories found → `array<model.CategoryResponse>`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/categories/root`

**Get root categories**

Retrieve all root categories (categories without parent)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Root categories found → `array<model.CategoryResponse>`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/categories/storage/{storageId}`

**Get categories by storage**

Retrieve all categories for a specific storage

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `storageId` | path | string | yes | Storage ID |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Categories found → `array<model.CategoryResponse>`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/categories/{id}`

**Delete a category**

Soft delete a category by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Category ID |

**Responses**

- `204` — Category deleted successfully
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Category not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/categories/{id}`

**Get a category by ID**

Retrieve a specific category by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Category ID |

**Responses**

- `200` — Category found → `model.CategoryResponse`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Category not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/categories/{id}`

**Update a category**

Update an existing category

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Category ID |
| `input` | body | model.UpdateCategoryRequest | yes | Category update data |

**Body schema:** `model.UpdateCategoryRequest`

**Responses**

- `200` — Category updated successfully → `model.CategoryResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Category not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/categories/{id}/restore`

**Restore a category**

Restore a soft-deleted category by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Category ID |

**Responses**

- `200` — Category restored successfully → `model.CategoryResponse`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Category not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

