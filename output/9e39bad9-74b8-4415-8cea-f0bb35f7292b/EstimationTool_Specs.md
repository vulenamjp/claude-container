# Mendix Estimation Tool — Application Specification

**Version**: 1.0
**Date**: 2026-05-26
**Author**: Laida-Mx
**Source basis**: `Base_of_estimation.md` (SC-WBS-Mendix_Estimation_VN.xlsx — sheet `#Base_of_estimation`)

---

## 1. Tổng quan (Overview)

### 1.1 Mục đích
Xây dựng một ứng dụng Mendix nội bộ cho phép PM / BA / Estimator nhập thông tin một dự án phần mềm (mới hoặc 再開発) và **tự động tính effort** cho từng công đoạn (REQ → BD → DD → CD → UT → IT → ST) dựa trên các bảng chuẩn năng suất, mật độ và độ phức tạp trong tài liệu Base of Estimation.

### 1.2 Phạm vi
- Quản lý các Project ước lượng.
- Hỗ trợ 3 phương pháp estimation: **By LOC/KVP**, **By Screen + Complexity**, **By Productivity (Page/Case)**.
- Hỗ trợ 2 loại dự án: **New Development** và **Modernization (再開発)**.
- Cho phép quản trị Master data (Productivity Norm, Density, Complexity Rate, Phase Ratio).
- Xuất kết quả ra Excel/PDF.
- **Out of scope**: tích hợp với hệ thống nhân sự, hệ thống quản lý dự án (Jira/Redmine), tính chi phí (cost).

### 1.3 User roles
| Role | Quyền |
| --- | --- |
| Estimator | Tạo/sửa/xem Project của mình, chạy tính toán, export |
| Project Manager | Xem tất cả Project, approve estimation |
| Admin | Quản lý Master data (Productivity Norm, Density, Ratio, Complexity) + User |
| Viewer | Read-only |

---

## 2. Yêu cầu chức năng (Functional Requirements)

### FR-01: Project Management
- FR-01.1: Tạo / sửa / xóa Project ước lượng.
- FR-01.2: Mỗi Project có: Tên, Mã, Khách hàng, Loại dự án (New / 再開発), Technology stack (Mendix / Java / .Net / Other), Estimator, Trạng thái (Draft / Submitted / Approved).
- FR-01.3: Clone Project (dùng làm template).
- FR-01.4: Versioning — mỗi lần approve sinh một snapshot không cho sửa.

### FR-02: Module Input (Screen / Batch / Report)
- FR-02.1: Thêm các Module thuộc Project, gán loại (Screen / Batch / Report).
- FR-02.2: Mỗi Module có: Tên, Loại, Complexity (Very easy / Easy / Normal / Hard / Very hard), LOC dự kiến (optional), Số trang dự kiến (optional).
- FR-02.3: Bulk import Module từ Excel (column: name, type, complexity, LOC).
- FR-02.4: Auto-detect complexity theo LOC theo bảng 3.5 (nếu user nhập LOC mà không nhập complexity).

### FR-03: Estimation Calculation
- FR-03.1: Hỗ trợ 3 phương pháp tính, user chọn 1 cho mỗi Project:
  - **Method A — By LOC/KVP**: nhập tổng LOC dự kiến → tính ra số trang tài liệu, số test case, số bug theo Density (mục 2 base).
  - **Method B — By Screen Count + Complexity**: nhập danh sách Module + Complexity → app suy ra LOC trung bình mỗi loại module × Complex Rate → ra LOC tổng → áp dụng Method A.
  - **Method C — By Productivity (Page/MD)**: user nhập số trang/case → tính effort trực tiếp theo bảng năng suất (mục 1).
- FR-03.2: Áp dụng **Complex Rate** (0.8 / 0.9 / 1.0 / 1.2 / 1.4) cho từng Module.
- FR-03.3: Tính LOC FE/BE theo tỉ lệ PR層 / BL層 (mục 4 base) — default PR = 40%.
- FR-03.4: Tính effort từng phase:
  - **New Development**: dùng phase ratio mục 2.4 (BD 0.167 / DD 0.175 / CD+UT 0.355 / IT 0.173 / ST 0.130).
  - **Modernization**: base CD+UT, các phase khác tính theo % mục 2.5 (REQ 17.2% / BD 52.5% / DD 48.8% / IT 49.2% / ST 63.9% của 製作).
- FR-03.5: Hiển thị effort dạng người-ngày (MD), người-tháng (MM, 1 MM = 20 MD), với breakdown theo phase × loại module (screen / batch / report).
- FR-03.6: Tính số test case dự kiến (UT / IT / ST) và số bug expected theo Density.
- FR-03.7: Có thể nhập **Overhead %** (PM, QA, review…) cộng thêm vào tổng effort. Default 15%.

### FR-04: Result & Report
- FR-04.1: Trang Result hiển thị:
  - Tổng LOC, VP, KVP
  - Bảng effort breakdown theo phase × loại module
  - Bảng test case / bug expected
  - Biểu đồ tỉ lệ effort theo phase (pie chart)
  - Tổng MD / MM
- FR-04.2: Export Excel theo template SC-WBS-Mendix_Estimation_VN.xlsx.
- FR-04.3: Export PDF báo cáo tóm tắt (1-2 trang).
- FR-04.4: So sánh 2 Project (delta LOC, delta effort).

### FR-05: Master Data Management
- FR-05.1: Quản lý các bảng master sau (Admin only):
  - Productivity Norm — Customer (bảng 1.1)
  - Productivity Norm — Internal (bảng 1.2)
  - Density — Customer / Internal (bảng 2.1–2.3)
  - Phase Ratio — New Dev (bảng 2.4)
  - Phase Ratio — Modernization (bảng 2.5)
  - Complex Rate (bảng 3.1)
  - LOC Range for auto-detect Complexity (bảng 3.5)
  - PR/BL ratio defaults (bảng 4.1–4.3)
- FR-05.2: Versioning master data — khi sửa, Project cũ vẫn dùng version cũ; Project mới dùng version mới.
- FR-05.3: Import / export master data dạng JSON.

### FR-06: Audit & History
- FR-06.1: Lưu log mỗi lần chạy tính toán (input + output snapshot).
- FR-06.2: Lịch sử thay đổi Master data.

### FR-07: Authentication
- FR-07.1: SSO (SAML / OIDC) với corporate AD. Fallback local user.
- FR-07.2: Role-based access (Estimator / PM / Admin / Viewer).

---

## 3. Phi chức năng (Non-functional Requirements)

| NFR | Yêu cầu |
| --- | --- |
| Performance | Tính toán 1 Project ≤ 200 Module hoàn thành trong < 2s |
| Concurrency | Hỗ trợ 50 user đồng thời |
| Availability | 99% giờ làm việc |
| Security | Estimator chỉ thấy Project của mình; PM/Admin thấy tất cả; HTTPS bắt buộc |
| Browser | Chrome / Edge / Firefox phiên bản hiện hành (mới nhất 2 versions) |
| Language | UI tiếng Nhật + tiếng Việt (i18n) |
| Backup | Daily full DB backup, giữ 30 ngày |
| Mendix version | Mendix 11 |

---

## 4. Data Model (Domain Model)

### 4.1 Entities chính

```
Project
├── id (auto)
├── code (string, unique)
├── name (string)
├── customerName (string)
├── projectType (enum: NewDev, Modernization)
├── techStack (enum: Mendix, Java, DotNet, Other)
├── estimationMethod (enum: ByLOC, ByScreenComplexity, ByProductivity)
├── overheadPercent (decimal, default 15)
├── prRatioOverride (decimal, optional — default 0.4)
├── status (enum: Draft, Submitted, Approved)
├── estimator → User
├── projectManager → User
├── createdDate, modifiedDate
└── 1—N → Module
    1—1 → EstimationResult (latest)
    1—N → EstimationSnapshot (history)

Module
├── id
├── name
├── moduleType (enum: Screen, Batch, Report)
├── complexity (enum: VeryEasy, Easy, Normal, Hard, VeryHard)
├── estimatedLOC (integer, optional)
├── estimatedPages (decimal, optional)
├── prRatio (decimal, optional — override per-module)
├── note (string)
└── N—1 → Project

EstimationResult
├── id
├── totalLOC, totalVP, totalKVP
├── totalEffortMD, totalEffortMM
├── effortREQ, effortBD, effortDD, effortCD, effortUT, effortIT, effortST (MD)
├── testCaseUT, testCaseIT, testCaseST
├── bugUT, bugIT, bugST
├── locPR, locBL
├── calculatedAt (datetime)
└── 1—1 → Project

EstimationSnapshot (immutable history)
├── id
├── snapshotJSON (string, full Project + Result frozen)
├── version (int)
└── N—1 → Project

// Master data
ProductivityNorm
├── version (int)
├── effectiveFrom, effectiveTo
├── audience (enum: Customer, Internal)
├── phase (enum: REQ, BD, DD, CD, UT_Create, UT_Exec, UT_Bug, IT_Create, IT_Exec, IT_Bug, ST_Create, ST_Exec, ST_Bug)
├── moduleType (enum: Screen, Batch, Report)
├── value (decimal)
└── unit (string)

DensityRule
├── version, audience, basis (enum: KVP, KLOC)
├── phase, moduleType, value, unit

PhaseRatio
├── projectType (NewDev / Modernization)
├── phase
├── ratioOfTotal (decimal) — for NewDev
├── ratioOfCDUT (decimal) — for Modernization

ComplexityRate
├── complexity (enum)
├── rate (decimal)

ComplexityLOCRange
├── complexity
├── locMin, locMax
└── default avgLOC (dùng cho Method B)

PRBLDefault
├── profileType (UIHeavy / Balanced / BLHeavy)
├── prPercent
```

### 4.2 Enumerations
- `ProjectType`: NewDev, Modernization
- `EstimationMethod`: ByLOC, ByScreenComplexity, ByProductivity
- `ModuleType`: Screen, Batch, Report
- `Complexity`: VeryEasy, Easy, Normal, Hard, VeryHard
- `Phase`: REQ, BD, DD, CD, UT, IT, ST (cộng sub-phases khi cần)
- `ProjectStatus`: Draft, Submitted, Approved
- `UserRole`: Estimator, ProjectManager, Admin, Viewer

---

## 5. Screen List

| ID | Tên màn hình | Mô tả ngắn | Role truy cập |
| --- | --- | --- | --- |
| SC-001 | Login | SSO / form đăng nhập | All |
| SC-002 | Dashboard | KPI tổng (số Project, tổng MM, Project chờ approve) | All |
| SC-003 | Project List | Danh sách + filter (status / customer / estimator) | All |
| SC-004 | Project Create / Edit | Form nhập thông tin chung | Estimator, Admin |
| SC-005 | Project Detail — Overview tab | Thông tin chung, status, history | All |
| SC-006 | Project Detail — Module tab | Bảng nhập Module + bulk import | Estimator |
| SC-007 | Project Detail — Calculation tab | Chọn method, input bổ sung, preview formula | Estimator |
| SC-008 | Project Detail — Result tab | Effort breakdown + chart + export | All |
| SC-009 | Project Compare | So sánh 2 Project | PM, Admin |
| SC-010 | Master Data — Productivity Norm | CRUD bảng năng suất | Admin |
| SC-011 | Master Data — Density | CRUD bảng mật độ | Admin |
| SC-012 | Master Data — Phase Ratio | CRUD tỉ lệ phase | Admin |
| SC-013 | Master Data — Complexity | CRUD complex rate + LOC range | Admin |
| SC-014 | User Management | CRUD user + role | Admin |
| SC-015 | Audit Log | Lịch sử thay đổi | Admin |

---

## 6. Calculation Logic (Reference)

### 6.1 Method A — By LOC/KVP
```
Input: TotalLOC, projectType, moduleTypeMix (% screen/batch/report)
KVP = TotalLOC / 1.6
LOC_PR = TotalLOC × prRatio
LOC_BL = TotalLOC × (1 - prRatio)

For each phase p ∈ {REQ, BD, DD, CD, UT, IT, ST}:
    For each moduleType m ∈ {Screen, Batch, Report}:
        LOC_m = TotalLOC × mix[m]
        // Pages
        pages_m = LOC_m / 1000 × Density[p][m]  // page/KLOC
        // Effort (customer band, page/MD productivity)
        effort_p_m = pages_m / Productivity[p][m]
    effort_p = Σ effort_p_m

If projectType = Modernization:
    effort_CDUT = Productivity-based
    effort_REQ  = effort_CDUT × 0.172
    effort_BD   = effort_CDUT × 0.525
    effort_DD   = effort_CDUT × 0.488
    effort_IT   = effort_CDUT × 0.492
    effort_ST   = effort_CDUT × 0.639

Apply overhead:
    totalEffort = (Σ effort_p) × (1 + overheadPercent)
```

### 6.2 Method B — By Screen + Complexity
```
For each module:
    baseLOC = ComplexityLOCRange[moduleType][complexity].avgLOC
    moduleLOC = baseLOC × ComplexityRate[complexity]
TotalLOC = Σ moduleLOC
→ feed vào Method A
```

### 6.3 Method C — By Productivity (Page/MD)
```
User trực tiếp nhập:
    pages_BD_screen, pages_DD_screen, ...
    testCases_UT_screen, ...
effort_p = pages_p / productivity_p  (page/MD)
testCaseEffort = cases / 60  (case/MD)
totalEffort = Σ all effort × (1 + overheadPercent)
```

### 6.4 Auto-detect complexity by LOC (bảng 3.5)
```
if LOC < 200       → VeryEasy
elif LOC < 800     → Easy
elif LOC < 2000    → Normal
elif LOC < 8000    → Hard
else               → VeryHard
```

---

## 7. Microflows chính (Mendix)

| Microflow | Mục đích |
| --- | --- |
| `ACT_Project_Create` | Tạo Project mới, gán Estimator hiện tại |
| `ACT_Project_Clone` | Clone Project + Module list |
| `ACT_Module_BulkImport` | Parse Excel → tạo Module |
| `SUB_Calc_LOCFromModules` | Tính TotalLOC từ Module list (Method B) |
| `SUB_Calc_PhaseEffort_NewDev` | Áp dụng phase ratio 2.4 |
| `SUB_Calc_PhaseEffort_Modernization` | Áp dụng tỉ lệ 2.5 |
| `SUB_Calc_TestCaseAndBug` | Tính test case + bug theo Density |
| `ACT_Estimation_Run` | Orchestrator: chọn method → gọi SUB tương ứng → ghi EstimationResult |
| `ACT_Estimation_Snapshot` | Khi Approve → ghi EstimationSnapshot |
| `ACT_Export_Excel` | Sinh Excel theo template |
| `ACT_Export_PDF` | Sinh PDF tóm tắt |
| `BR_ComplexityFromLOC` | Business rule — auto-detect complexity từ LOC |
| `BR_HasEditPermission` | Check role để cho edit |

---

## 8. Acceptance Criteria (mẫu)

| ID | Criteria |
| --- | --- |
| AC-01 | Khi user nhập 10,000 LOC, project mới, mix 100% screen, kết quả effort BD = TotalEffort × 0.167 ± 0.01 |
| AC-02 | Khi user đổi complexity Hard → Normal, LOC tự động tính lại và effort cập nhật trong vòng 1s |
| AC-03 | Khi Project status = Approved, mọi field input bị disable |
| AC-04 | Excel export khớp template SC-WBS với đầy đủ 7 phase + 3 moduleType |
| AC-05 | Estimator chỉ thấy Project mình tạo trong SC-003 |
| AC-06 | Auto-detect complexity với LOC=500 phải trả về Easy |
| AC-07 | Tỉ lệ PR/BL mặc định = 40/60 và có thể override per-project và per-module |

---

## 9. Open issues / Risks

1. **Average LOC per screen-complexity** (cho Method B) chưa có trong base — cần ấn định baseline từ dataset 32 màn (Median 717 LOC for Normal, Q3 1,480 LOC for Hard). **Action**: chốt giá trị với PM trước khi build.
2. Báo cáo bug expected cho Report/Batch chưa có chi tiết complex breakdown trong base (mục 3.3/3.4 ghi "tùy Opp") — app cần fallback dùng Normal rate.
3. Mendix có giới hạn import Excel — file lớn (> 5000 row) cần dùng Java action thay vì microflow gốc.
4. Xác định template Excel output chính xác theo SC-WBS-Mendix_Estimation_VN.xlsx — cần file mẫu.

---

## 10. Phụ lục — Hằng số cốt lõi (tham chiếu nhanh từ Base)

| Hằng số | Giá trị |
| --- | --- |
| 1 KLOC | 1,000 LOC |
| 1 VP | 1.6 Step |
| 1 KVP | 1.6 KLOC |
| Default PR ratio | 40% |
| Default Overhead | 15% |
| 1 MM | 20 MD |
| Phase ratio NewDev | BD 16.7% / DD 17.5% / CD+UT 35.5% / IT 17.3% / ST 13.0% |
| Phase ratio Modern. (vs 製作) | REQ 17.2% / BD 52.5% / DD 48.8% / IT 49.2% / ST 63.9% |
| Complex Rate | VE 0.8 / E 0.8–0.9 / N 1.0 / H 1.2 / VH 1.4 |

---

*End of spec.*
