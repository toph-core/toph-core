# POS App — Implementation Plan

## 1. Login Flow & Role-Based MainScreen

### Maqsad
Hozir: Splash → LoginScreen → LoginPinScreen → MainScreen (static)
Yangi: Splash → LoginScreen → LoginPinScreen → MainScreen (role'ga qarab o'zgaradi)

### Flow (o'zgarmaydi)
```
Splash
  ├─ brandId yo'q ──→ LoginScreen (brand_id + password)
  │                         │
  │                         └──→ LoginPinScreen (PIN kiritish)
  │                                   │
  │                                   └──→ API call: {brand_id, password, pincode}
  │                                   └──→ Backend returns: {accessToken, user{id, name, role}}
  │
  ├─ brandId bor, token yo'q ──→ LoginPinScreen
  │
  └─ brandId + token bor ──→ MainScreen
                              (user.role'ga qarab UI o'zgaradi)
```

### Backend Response'ni o'zgarish (kerak)
Hozir: `{accessToken, refreshToken}`
Yangi: `{accessToken, refreshToken, user: {id, name, role, ...}}`

### MainScreen — Role-based UI

**Hozirgi MainScreen ishchi:**
- HallWidget → Tables grid
- Filter tabs

**O'zgarishi:** MainScreen'ni BlocBuilder'ga o'rash
```dart
BlocBuilder<UserBloc, UserState>(
  builder: (context, state) {
    final role = state.userModel?.role;

    switch(role) {
      case UserRole.cashier:
        return CashierScreen();  // Kassa UI
      case UserRole.waiter:
        return WaiterScreen();   // Ofitsant UI
      case UserRole.admin:
      case UserRole.manager:
        return AdminScreen();    // Admin UI
      default:
        return MainScreen();     // Default (tables grid)
    }
  }
)
```

### O'zgartiriluvchi fayllar
| Fayl | O'zgarish |
|------|-----------|
| `lib/core/api/dto/login_response.dart` | `user` field qo'shiladi |
| `lib/features/view/auth/presentation/cubit/auth_cubit.dart` | Login response'dan `user` saqlanadi |
| `lib/features/view/auth/presentation/bloc/user_bloc.dart` | `user.role` ishlatiladi |
| `lib/features/view/main/presentation/pages/main/main_screen.dart` | Role switch qo'shiladi |

### Yangi screen'lar (keyingi bosqichda)
| Rol | Screen | Fayl |
|-----|--------|------|
| `cashier` | CashierScreen | `lib/features/view/cashier/presentation/pages/cashier_screen.dart` |
| `waiter` | WaiterScreen | `lib/features/view/waiter/presentation/pages/waiter_screen.dart` |
| `admin` | AdminScreen | `lib/features/view/admin/presentation/pages/admin_screen.dart` |

---

---

## 2. CashierScreen — Batafsil Layout

### Umumiy struktura
4 ta tab + left sidebar + content area

### Top Tabs (4)
1. **Блюда** (Dishes) - Pink - Menu/dish management
2. **Касса** (Cash) - Red - Payment/cashier operations
3. **Счета** (Bills) - Yellow - Bills and accounts
4. **Настройки** (Settings) - Yellow - Settings

### Left Sidebar Menu
- Отдел (Department)
- Категория (Category)
- Блюда (Dishes)
- Модификаторы (Modifiers)
- Позиции блюд (Dish positions)
- Стол-лист (Table list)

### Content Area (role'ga qarab o'zgaradi)

**Tab 1: Блюда (Dishes)**
- Группы (Groups)
- Расходы и приходы (Expenses and income)

**Tab 2: Касса (Cash) — MAIN**
- Полнота (Completeness) — cyan highlight
- Клиенты (Clients)
- Доставка (Delivery)
- Раздача (Distribution)
- To'lovni qabul qilish
- Shift status

**Tab 3: Счета (Bills)**
- Все счета (All bills) - blue
- Счет (Bill) - blue
- Доставка (Delivery) - blue
- Раздача (Distribution) - blue

**Tab 4: Настройки (Settings)**
- Персонал ресторана (Restaurant staff)
- Залы (Halls)
- Настройки принтеров (Printer settings)

### Bottom Right Info Panel
```
Кассир: Касса
11:02:31
30 Март 2026, Понедельник
```
- Cashier name
- Current time
- Date

### Highlighted Components
- **Полнота** (Cyan/Turquoise) - Main cashier operation
- **Монитор** (Lime green) - Monitor/display dashboard

---

## 3. Role-Specific Screens

### Rollar va mos screen'lar
| Rol | Screen | Features |
|-----|--------|----------|
| `cashier` | CashierScreen | Shift, payments, reports |
| `admin` / `manager` | AdminScreen | Full access |
| `waiter` | WaiterScreen | Tables, orders |

### WaiterScreen (Ofitsant) — kerakli featurlar (hozir ishlanmoqda)
- [x] Enhanced table cards (waiting time, alerts, badges)
- [x] Item notes modal (Izoh qo'shish)
- [x] Split bill modal (To'lovni bo'lish)
- [x] Special requests checkboxes
- [ ] Band stolga kirganda avvalgi buyurtmalar ko'rinishi
- [ ] Oshxonaga bildir (Kitchen notification)

### CashierScreen (Кешier) — kerakli featurlar
- Shift ochish / yopish
- To'lovni qabul qilish (naqd, karta, online)
- Kunlik hisobot
- Client management
- Delivery tracking
- Staff management
- Hall/section management

### Admin uchun kerakli featurlar
- Barcha funksiyalar
- Xodimlar boshqaruvi
- Statistika va hisobotlar
- Menu boshqaruvi

---

## 4. Band stolga kirganda orders ko'rsatish (fix kerak)

### Muammo
Band stol ustiga bosilganda avvalgi tanlangan menu itemlari ko'rinmaydi.

### Yechim
**Option A (Hozirgi):** SavedOrdersBloc — lokal xotirada saqlash
**Option B (To'liq):** `GET /api/v1/bills/{tableId}` — API'dan fetch qilish

### API ma'lumotlari
- Endpoint: `/api/v1/bills/{id}`
- Mavjud: `getArchiveWithId()` in `main_datasources.dart`
- Response: `ArchiveDetailEntity` (goods, totalPrice, guestCount...)

### Implementatsiya
1. Band stol bosilganda table ID bilan `/api/v1/bills/{tableId}` chaqiriladi
2. Response'dagi `goods` → `OrderItem` formatiga convert qilinadi
3. `DetailEvent.initSavedGoods()` orqali sidebar'ga yuklanadi

---

## 5. Texnik qarzlar (Technical Debt)

- [ ] Debug `print()` statementlarini olib tashlash (order_side_bar_widget.dart)
- [ ] EnhancedTableCard'dagi waiting time real data bilan bog'lash
- [ ] Split bill modal'da real total amount uzatish
- [ ] Freezed files regenerate (`build_runner build`)
