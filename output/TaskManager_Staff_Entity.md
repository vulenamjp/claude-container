# Entity Design: `TaskManager.Staff`

> Tài liệu thiết kế entity `Staff` thuộc module `TaskManager` — dùng để dựng entity trong Mendix Studio Pro 11.

---

## 1. Thông tin chung

| Mục | Giá trị |
|---|---|
| Module | `TaskManager` |
| Tên entity | `Staff` |
| Full name | `TaskManager.Staff` |
| Persistable | `true` |
| Generalization | `System.User` |
| Documentation | Lưu thông tin nhân viên trong hệ thống TaskManager. Kế thừa `System.User` để dùng được chức năng đăng nhập của Mendix. |

> Vì `Staff` kế thừa `System.User`, entity sẽ tự động có sẵn các attribute hệ thống: `Name` (username đăng nhập), `Password`, `LastLogin`, `Blocked`, `Active`, `IsAnonymous`, `WebServiceUser`, `FailedLogins`, `LanguageCode`, `TimeZoneID`...

---

## 2. Attribute bổ sung của `Staff`

| # | Tên Attribute | Type | Length / Enum | Default value | Required (trên form) | Ghi chú |
|---|---|---|---|---|---|---|
| 1 | `StaffCode` | String | 20 | — | Yes | Mã nhân viên, duy nhất theo logic nghiệp vụ |
| 2 | `FullName` | String | 100 | — | Yes | Họ và tên đầy đủ, dùng để hiển thị |
| 3 | `Email` | String | 100 | — | Yes | Email liên lạc của nhân viên |
| 4 | `PhoneNumber` | String | 20 | — | No | Số điện thoại |
| 5 | `Position` | Enumeration `ENU_Position` | `Manager` / `Leader` / `Member` | `Member` | Yes | Chức vụ trong tổ chức |
| 6 | `HireDate` | DateTime | — | `[%CurrentDateTime%]` | Yes | Ngày vào làm (mặc định = ngày hiện tại) |
| 7 | `IsActive` | Boolean | — | `true` | Yes | Trạng thái nhân viên còn làm việc hay không |

> Lưu ý: `Required` trong bảng trên là yêu cầu nghiệp vụ — sẽ được enforce bằng **Validation rule** trên entity (xem mục 4), không cần bật `Required` trực tiếp ở attribute (Mendix 11 khuyến nghị validation qua microflow hoặc validation rule).

---

## 3. Enumeration: `TaskManager.ENU_Position`

| Value (Name) | Caption (EN) | Caption (VI) |
|---|---|---|
| `Manager` | Manager | Quản lý |
| `Leader` | Leader | Trưởng nhóm |
| `Member` | Member | Thành viên |

---

## 4. Validation rules (Entity → Tab "Validation rules")

| Attribute | Rule | Error message |
|---|---|---|
| `StaffCode` | Required | "Staff code is required." |
| `StaffCode` | Unique | "Staff code already exists." |
| `FullName` | Required | "Full name is required." |
| `Email` | Required | "Email is required." |
| `Email` | Regular expression: email pattern | "Invalid email format." |

> `Unique` cho `StaffCode` cần check bằng **Before Commit microflow** nếu muốn validate runtime (Mendix's built-in "Unique" chỉ áp dụng nếu attribute nằm trực tiếp trên entity, sẽ hoạt động được vì StaffCode là attribute mới).

---

## 5. Access rules (Entity → Tab "Access rules")

Đề xuất 2 module role tối thiểu:

### Role: `Administrator`
| Quyền | Giá trị |
|---|---|
| Allow creating new objects | Yes |
| Allow deleting existing objects | Yes |
| XPath constraint | (trống — full access) |
| Member: tất cả attribute | Read, Write |

### Role: `User`
| Quyền | Giá trị |
|---|---|
| Allow creating new objects | No |
| Allow deleting existing objects | No |
| XPath constraint | `[id = '[%CurrentUser%]']` (chỉ xem chính mình) |
| Member: `StaffCode`, `FullName`, `Email`, `PhoneNumber`, `Position`, `HireDate`, `IsActive` | Read |
| Member: `Password` (kế thừa) | (không cho phép) |

> Module role được cấu hình ở **Security → Module security → `TaskManager` → Module roles**.

---

## 6. Association (chưa tạo trong scope này)

Đề xuất khi tạo các entity liên quan:

| Tên Association | Owner | Multiplicity | Mô tả |
|---|---|---|---|
| `Staff_Department` | Default | `Staff *` ⟶ `1 Department` | Một nhân viên thuộc 1 phòng ban |
| `Task_AssignedTo_Staff` | Default | `Task *` ⟶ `1 Staff` | Một task được giao cho 1 nhân viên |
| `Task_CreatedBy_Staff` | Default | `Task *` ⟶ `1 Staff` | Người tạo task |

---

## 7. Event handler đề xuất (tùy chọn)

| Event | Microflow | Mục đích |
|---|---|---|
| Before commit | `ACT_Staff_BeforeCommit` | Validate `StaffCode` unique, normalize email lowercase |
| After create | `ACT_Staff_AfterCreate` | Gán default module role cho User mới (nếu cần) |

---

## 8. Hướng dẫn thao tác ngắn trong Studio Pro

1. **Mở module `TaskManager`** trong App Explorer.
2. **Tạo Enumeration `ENU_Position`**: Right click module → `Add other → Enumeration` → đặt tên `ENU_Position` → thêm 3 value như mục 3.
3. **Mở Domain Model** của module `TaskManager`.
4. **Kéo Entity từ toolbox** vào canvas → đặt tên `Staff`.
5. Trong tab **General** của entity:
   - Persistable: `Yes`
   - Generalization: click `Select…` → chọn `System.User`.
6. Trong tab **Attributes**: thêm lần lượt 7 attribute theo mục 2.
7. Trong tab **Validation rules**: thêm rule theo mục 4.
8. Trong tab **Access rules**: thêm rule theo mục 5 (cần đã tạo module role trong Security).
9. **Save** → kiểm tra Errors pane (`F4`) đảm bảo không có lỗi.

---

**Phiên bản tài liệu**: 1.0 — 2026-05-26
**Tác giả**: Laida-Mx
