# Todo Application — Functional Spec (Mendix 11)

| Mục | Nội dung |
|---|---|
| Tên ứng dụng | TodoApp |
| Nền tảng | Mendix 11 |
| Đối tượng người dùng | Cá nhân (single user) |
| Ngôn ngữ UI | Tiếng Việt |
| Phiên bản tài liệu | 1.0 — 2026-05-26 |

---

## 1. Mục tiêu

Xây dựng ứng dụng quản lý công việc cá nhân cho phép người dùng tạo, theo dõi, cập nhật và hoàn thành các đầu việc (task) hằng ngày với các thuộc tính cơ bản như tiêu đề, mô tả, hạn chót, mức độ ưu tiên và trạng thái.

## 2. Phạm vi

**Trong phạm vi (In scope)**
- CRUD task.
- Đánh dấu task đã hoàn thành / chưa hoàn thành.
- Lọc theo trạng thái, mức độ ưu tiên, hạn chót.
- Sắp xếp theo ngày tạo / hạn chót / priority.
- Tìm kiếm theo tiêu đề.
- Đăng nhập đơn giản bằng Mendix `Administration.Account` (1 user mặc định: `MxAdmin`).

**Ngoài phạm vi (Out of scope)**
- Multi-user, phân quyền theo role nâng cao.
- Assign task, comment, notification.
- Tích hợp lịch (Google/Outlook).
- Mobile native (chỉ Responsive Web).

## 3. Actor & Role

| Role | Mendix User Role | Mô tả |
|---|---|---|
| User | `TodoUser` | Người dùng cuối, thao tác toàn bộ task của mình. |

> Module access: `TodoUser` có quyền `Read/Write/Create/Delete` trên entity `Task`.

## 4. Domain Model

### 4.1 Entities

#### `Task` (persistable)

| Attribute | Type | Length / Enum | Required | Default | Ghi chú |
|---|---|---|---|---|---|
| `Title` | String | 200 | ✅ | — | Tiêu đề task. |
| `Description` | String | 2000 | ❌ | — | Mô tả chi tiết, multiline. |
| `DueDate` | DateTime | — | ❌ | — | Hạn chót, **localized = Yes**. |
| `Priority` | Enumeration | `ENUM_Priority` | ✅ | `Medium` | Low / Medium / High. |
| `Status` | Enumeration | `ENUM_Status` | ✅ | `Open` | Open / InProgress / Done. |
| `CompletedDate` | DateTime | — | ❌ | — | Set khi `Status` chuyển sang `Done`. |
| `CreatedDate` | DateTime | — | ✅ | `[%CurrentDateTime%]` | System. |
| `ChangedDate` | DateTime | — | ✅ | `[%CurrentDateTime%]` | System. |

> Bật **System Members**: `createdDate`, `changedDate`, `owner`, `changedBy` — dùng `owner` để lọc task theo user (xem §6).

### 4.2 Enumerations

**`ENUM_Priority`**
| Name | Caption |
|---|---|
| `Low` | Thấp |
| `Medium` | Trung bình |
| `High` | Cao |

**`ENUM_Status`**
| Name | Caption |
|---|---|
| `Open` | Mới |
| `InProgress` | Đang làm |
| `Done` | Hoàn thành |

### 4.3 Sơ đồ quan hệ

Chỉ có 1 entity `Task`, không có association cứng. Liên kết với user thông qua **System.owner** (mặc định Mendix).

## 5. Pages / Screens

| Page | Layout | Mục đích |
|---|---|---|
| `Home_Web` | `Atlas_Default` | Landing — redirect sang `Task_Overview`. |
| `Task_Overview` | `Atlas_Default` | Danh sách task + filter + search. |
| `Task_NewEdit` | `PopupLayout` | Form tạo / sửa task. |
| `Task_Detail` | `PopupLayout` | Xem chi tiết (read-only). |

### 5.1 `Task_Overview` — Wireframe

```
┌──────────────────────────────────────────────────────────┐
│ Todo App                                       [Logout] │
├──────────────────────────────────────────────────────────┤
│ [+ New Task]  Search:[______]  Status:[All▼] Priority:[All▼]│
├──────────────────────────────────────────────────────────┤
│ ☐  Title              Priority   Due Date    Status      │
│ ☐  Mua sữa            Medium    2026-05-27  Open    [✏][🗑]│
│ ☑  Họp team           High      2026-05-26  Done    [✏][🗑]│
│ ...                                                       │
└──────────────────────────────────────────────────────────┘
```

**Widgets**
- Data Grid 2 hoặc List View với entity `Task`.
- Search bar: dropdown filter cho `Status`, `Priority`; text filter cho `Title`.
- Checkbox đầu mỗi dòng = toggle `Status` Open ↔ Done (trigger microflow).

### 5.2 `Task_NewEdit`

| Field | Widget | Validation |
|---|---|---|
| Title | Text Box | Required, max 200. |
| Description | Text Area | Optional. |
| Due Date | Date Picker | Optional, không cho phép quá khứ khi tạo mới. |
| Priority | Dropdown | Required. |
| Status | Dropdown | Required. |
| [Save] [Cancel] | Buttons | — |

## 6. Microflows

| Tên | Trigger | Logic chính |
|---|---|---|
| `ACT_Task_New` | Nút **+ New Task** | Create `Task`, set defaults, mở `Task_NewEdit`. |
| `ACT_Task_Save` | Nút **Save** trên form | Validate → nếu `Status = Done` & `CompletedDate` rỗng → set `CompletedDate = [%CurrentDateTime%]`; commit; close popup; refresh. |
| `ACT_Task_Delete` | Nút 🗑 | Confirm dialog → delete + refresh. |
| `ACT_Task_ToggleDone` | Checkbox trên dòng | Nếu `Open/InProgress` → set `Done` + `CompletedDate`; nếu `Done` → set `Open` + clear `CompletedDate`. Commit + refresh. |
| `DS_Task_MyTasks` | Data source của list | Retrieve `Task` với XPath constraint theo `owner`. Áp dụng filter từ overview. |

### 6.1 XPath cho `DS_Task_MyTasks`

```xpath
[System.owner = '[%CurrentUser%]']
```

> Tham khảo skill **mx-xpath** trước khi viết các constraint phức tạp (filter theo enum, date range, …) — Mendix 11 XPath khác chuẩn XPath 1.0/2.0.

## 7. Business Rules

| ID | Rule | Mô tả |
|---|---|---|
| BR-01 | Title bắt buộc | Không được rỗng, trim whitespace. |
| BR-02 | DueDate hợp lệ | Khi tạo mới, không cho phép DueDate < hôm nay. |
| BR-03 | CompletedDate tự động | Set = `[%CurrentDateTime%]` khi `Status` chuyển sang `Done`. Reset null khi quay về `Open`. |
| BR-04 | Quyền truy cập | User chỉ thấy / sửa task của chính mình (`System.owner = CurrentUser`). |
| BR-05 | Default Priority | Khi tạo mới mà không chọn → `Medium`. |
| BR-06 | Default Status | Khi tạo mới → `Open`. |

## 8. Navigation

- **Anonymous users**: Disabled.
- **After login**: `TodoUser` → mặc định mở `Task_Overview`.
- **Menu**: 1 menu item “Công việc của tôi” → `Task_Overview`.

## 9. Security

| Mục | Cấu hình |
|---|---|
| App security level | `Production` (Prod) |
| Anonymous access | Off |
| Module roles | `TodoUser` (xem §3) |
| Entity access — `Task` | XPath `[System.owner = '[%CurrentUser%]']`, allow CRUD. |
| Page access | `Task_Overview`, `Task_NewEdit`, `Task_Detail` → `TodoUser`. |
| Microflow access | Tất cả `ACT_Task_*`, `DS_Task_*` → `TodoUser`. |

## 10. Non-functional requirements

| Mục | Yêu cầu |
|---|---|
| Performance | List view < 1s với 1000 task. |
| Responsive | Hoạt động trên Desktop, Tablet, Phone (Atlas Responsive). |
| Browser | Chrome / Edge / Safari (2 phiên bản gần nhất). |
| Localization | Tiếng Việt (mặc định). |
| Audit | Dùng System members `createdDate`, `changedDate`, `owner`, `changedBy`. |

## 11. Cấu trúc Module (Mendix Studio Pro)

```
TodoApp
├── MyFirstModule (xóa, không dùng)
└── Todo
    ├── Domain Model
    │   └── Task
    ├── Enumerations
    │   ├── ENUM_Priority
    │   └── ENUM_Status
    ├── Pages
    │   ├── Task_Overview
    │   ├── Task_NewEdit
    │   └── Task_Detail
    ├── Microflows
    │   ├── ACT_Task_New
    │   ├── ACT_Task_Save
    │   ├── ACT_Task_Delete
    │   ├── ACT_Task_ToggleDone
    │   └── DS_Task_MyTasks
    └── Security
        └── Module Role: TodoUser
```

## 12. Roadmap mở rộng (tham khảo)

- Phase 2: Category / Tag cho task.
- Phase 3: Multi-user + assign + comment.
- Phase 4: Email reminder qua scheduled event.
- Phase 5: Mobile native app (Mendix Native Mobile).

---

**Tài liệu tham khảo**
- Mendix 11 documentation: <https://docs.mendix.com/>
- Atlas Core UI: <https://docs.mendix.com/appstore/modules/atlas-core/>
