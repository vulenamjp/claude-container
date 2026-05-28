# FAQ — Mendix Estimation Tool

**Version**: 1.0
**Date**: 2026-05-26
**対象資料**: `EstimationTool_Specs.md` (v1.0) / `Base_of_estimation.md` (SC-WBS-Mendix_Estimation_VN.xlsx)

> 本 FAQ は、Mendix Estimation Tool プロジェクトの仕様書および見積もりベース資料を元に、よくある質問とその回答をまとめたものです。
> 関連プロジェクト「Todo 管理システム」については §7 を参照してください。

---

## 1. プロジェクト全体

### Q1-1. このアプリケーションは何ですか？
PM / BA / Estimator が新規開発・再開発プロジェクトの工数 (effort) を**自動算出するための社内 Mendix アプリ**です。要件定義 (REQ) から基本設計 (BD)、詳細設計 (DD)、コーディング (CD)、単体テスト (UT)、結合テスト (IT)、システムテスト (ST) までの 7 フェーズの工数を、生産性・密度・複雑度の標準テーブルに基づいて算出します。

### Q1-2. どの Mendix バージョンを使用しますか？
**Mendix 11** を使用します (NFR 仕様)。

### Q1-3. 対応する見積もり手法は何ですか？
3 つの手法をサポートします。
- **Method A**: By LOC/KVP — 総 LOC を入力
- **Method B**: By Screen + Complexity — モジュール一覧 + 複雑度を入力
- **Method C**: By Productivity (Page/Case) — 直接 Page 数 / Case 数を入力

### Q1-4. 対応するプロジェクト種別は？
- **New Development** (新規開発)
- **Modernization** (再開発) — レガシーシステムの再構築

### Q1-5. スコープ外は何ですか？
- 人事システムとの連携
- プロジェクト管理ツール (Jira / Redmine) との連携
- コスト計算 (金額換算)

---

## 2. ユーザロール・権限

### Q2-1. ユーザロールは何種類ありますか？
4 種類です。

| ロール | 主な権限 |
|---|---|
| **Estimator** | 自分の Project を作成・編集・閲覧、計算実行、Export |
| **Project Manager** | 全 Project 閲覧、Estimation の Approve |
| **Admin** | Master data + User 管理 |
| **Viewer** | 読み取り専用 |

### Q2-2. Estimator は他人の Project を見られますか？
**いいえ。** Estimator は自分が作成した Project のみ閲覧可能です (NFR Security / AC-05 / SC-003 仕様)。

### Q2-3. 認証方式は？
SSO (SAML / OIDC) で社内 AD と連携。フォールバックとしてローカルユーザ認証もサポートします (FR-07.1)。

---

## 3. 機能 (Functional Requirements)

### Q3-1. Project はどのような情報を持ちますか？
コード (Mendix Attribute: `Code`)、名称 (`Name`)、顧客名 (`CustomerName`)、プロジェクト種別 (`ProjectType`)、技術スタック (`TechStack`)、見積もり手法 (`EstimationMethod`)、Overhead %、PR ratio、ステータス、Estimator / PM 参照、を保持します (FR-01.2)。

### Q3-2. Project の Clone はできますか？
はい。テンプレートとして既存 Project を Clone できます (FR-01.3、Microflow: `ACT_Project_Clone`)。

### Q3-3. Project の履歴管理 (Versioning) は？
**Approve 時に Snapshot 化**されます。`EstimationSnapshot` エンティティに JSON で凍結保存され、以後の編集はできません (FR-01.4 / AC-03)。

### Q3-4. Module の Bulk Import はサポートしていますか？
はい。Excel (column: name, type, complexity, LOC) からの一括取り込みをサポート (FR-02.3、Microflow: `ACT_Module_BulkImport`)。
※ 5000 行を超える大規模ファイルは Java Action 実装が必要 (Open Issue #3)。

### Q3-5. Module の Complexity はどう決定しますか？
- ユーザが明示的に選択 (`VeryEasy / Easy / Normal / Hard / VeryHard`)
- または LOC を入力すると **Auto-detect** (FR-02.4、Business Rule: `BR_ComplexityFromLOC`)
  - `< 200` → VeryEasy
  - `< 800` → Easy
  - `< 2000` → Normal
  - `< 8000` → Hard
  - 以上 → VeryHard

### Q3-6. Export 形式は？
- **Excel** (SC-WBS-Mendix_Estimation_VN.xlsx テンプレート準拠) — FR-04.2
- **PDF** (1〜2 ページのサマリ) — FR-04.3

### Q3-7. Project 同士を比較できますか？
はい。2 つの Project の LOC 差分・工数差分を比較する画面 `SC-009` が用意されています (FR-04.4、PM/Admin のみ)。

---

## 4. 計算ロジック

### Q4-1. KVP とは何ですか？
**Kilo Value Point** の略。`1 VP = 1.6 Step`、`1 KVP = 1.6 KLOC`。生産性・密度を統一単位で扱うための内部変換単位です (Base 0 章 / §10 付録)。

### Q4-2. PR / BL とは？
- **PR (Presentation 層)** : フロントエンド側 LOC
- **BL (Business Logic 層)** : バックエンド側 LOC
- **デフォルト比率**: PR = 40%, BL = 60% (Constant: `DEFAULT_PR_RATIO`)
- Project 単位・Module 単位で override 可能 (AC-07)

### Q4-3. 新規開発と再開発で計算式はどう違いますか？

**新規開発** — Phase Ratio (Base §2.4) を全体に適用:
```
BD  = TotalEffort × 0.167
DD  = TotalEffort × 0.175
CD+UT = TotalEffort × 0.355
IT  = TotalEffort × 0.173
ST  = TotalEffort × 0.130
```

**再開発 (Modernization)** — CD+UT を基準に他フェーズを算出 (Base §2.5):
```
REQ = CD+UT × 0.172
BD  = CD+UT × 0.525
DD  = CD+UT × 0.488
IT  = CD+UT × 0.492
ST  = CD+UT × 0.639
```

### Q4-4. Overhead とは何ですか？
PM / QA / レビュー等の管理コストの加算率です。**デフォルト 15%** (Constant: `DEFAULT_OVERHEAD_PERCENT`)、Project 単位で変更可能 (FR-03.7)。

### Q4-5. Complex Rate とは？
モジュールの複雑度による工数補正倍率。

| 複雑度 | Rate |
|---|---:|
| VeryEasy | 0.8 |
| Easy | 0.8〜0.9 |
| Normal | 1.0 |
| Hard | 1.2 |
| VeryHard | 1.4 |

### Q4-6. 1 人月 (MM) は何人日 (MD) ですか？
**1 MM = 20 MD** (Base §10 付録の定数)。

### Q4-7. テストケース数とバグ件数はどう算出されますか？
Density テーブル (Base §2.1〜§2.3) に基づいて算出します (FR-03.6、Microflow: `SUB_Calc_TestCaseAndBug`)。
- UT / IT / ST それぞれのケース数
- 期待バグ件数 (UT / IT / ST)

---

## 5. Mendix 実装 (命名規約・物理名)

### Q5-1. Module の物理名規約は？
**`UpperCamelCase` の英語名**を使用 (mx-cd-convention 準拠)。
- ドメイン Module: `EstimationCore` (推奨)
- マスタ Module: `EstimationMaster`
- 共通 Module: `EstimationShared`
- テスト Module: `EstimationUnitTest`

### Q5-2. Entity の命名は？
`UpperCamelCase` の単数形。`m_/t_/h_/w_` などのテーブル接頭辞は **使用しない**。
例: `Project`, `Module`, `EstimationResult`, `ProductivityNorm`

### Q5-3. Microflow の命名規則は？
**`{PREFIX}_{Entity}_{Operation}`** 形式。

仕様書記載の代表的な Microflow:

| Microflow | Prefix の意味 | 用途 |
|---|---|---|
| `ACT_Project_Create` | ACT = Action | Project 新規作成 |
| `ACT_Project_Clone` | ACT | Project Clone |
| `ACT_Module_BulkImport` | ACT | Excel 一括取り込み |
| `SUB_Calc_LOCFromModules` | SUB = Sub-microflow | LOC 合計算出 |
| `SUB_Calc_PhaseEffort_NewDev` | SUB | Phase Ratio (新規) |
| `SUB_Calc_PhaseEffort_Modernization` | SUB | Phase Ratio (再開発) |
| `SUB_Calc_TestCaseAndBug` | SUB | テスト数・バグ数算出 |
| `ACT_Estimation_Run` | ACT | 計算 Orchestrator |
| `ACT_Estimation_Snapshot` | ACT | Approve 時の Snapshot |
| `ACT_Export_Excel` | ACT | Excel 出力 |
| `ACT_Export_PDF` | ACT | PDF 出力 |
| `BR_ComplexityFromLOC` | BR = Business Rule | LOC→Complexity 判定 |
| `BR_HasEditPermission` | BR | 編集権限チェック |

※ Deprecated Prefix (`IVK_` / `SCH_` / `MF_`) は使用禁止。

### Q5-4. Constant に格納すべき値は？
ハードコードせず Constant 化が必須の値:
- `DEFAULT_PR_RATIO` = 0.4
- `DEFAULT_OVERHEAD_PERCENT` = 15
- `MD_PER_MM` = 20
- `VP_TO_LOC_RATIO` = 1.6 (1 VP = 1.6 Step)
- Excel/PDF テンプレートパス、外部 API URL 等もすべて Constant 化 (mx-cd-convention `BP_MF_010`)

### Q5-5. Enumeration の命名は？
`ENUM_{BusinessContext}` 形式、メンバーは `UpperCamelCase`。
- `ENUM_ProjectType` (NewDev, Modernization)
- `ENUM_EstimationMethod` (ByLOC, ByScreenComplexity, ByProductivity)
- `ENUM_ModuleType` (Screen, Batch, Report)
- `ENUM_Complexity` (VeryEasy, Easy, Normal, Hard, VeryHard)
- `ENUM_Phase` (REQ, BD, DD, CD, UT, IT, ST)
- `ENUM_ProjectStatus` (Draft, Submitted, Approved)
- `ENUM_UserRole` (Estimator, ProjectManager, Admin, Viewer)

### Q5-6. Page の命名は？
`{Entity}_{Suffix}` 形式。
- `Project_Overview`, `Project_NewEdit`, `Project_View`
- `Master_ProductivityNorm_Overview` 等
- Home: `Home_Web_Estimator`, `Home_Web_Admin` 等

---

## 6. 画面 (Screen List)

### Q6-1. 全部で何画面ありますか？
**15 画面** (SC-001 〜 SC-015)。

| 区分 | 画面数 |
|---|---:|
| 認証 / ダッシュボード | 2 (SC-001, SC-002) |
| Project 管理 (一覧 / 作成 / 詳細 4 タブ) | 6 (SC-003 〜 SC-008) |
| 比較 | 1 (SC-009) |
| Master データ管理 | 4 (SC-010 〜 SC-013) |
| User / 監査 | 2 (SC-014, SC-015) |

### Q6-2. Project Detail はどのような構成ですか？
4 つのタブで構成 (SC-005〜SC-008):
- **Overview** — 基本情報・ステータス・履歴
- **Module** — モジュール入力 + Bulk Import
- **Calculation** — 手法選択・入力・プレビュー
- **Result** — 工数 breakdown + チャート + Export

### Q6-3. Master Data の画面は誰がアクセスできますか？
**Admin のみ** (SC-010 〜 SC-014)。

---

## 7. 非機能要件 (NFR)

### Q7-1. パフォーマンス要件は？
**200 Module 規模の Project 計算 < 2 秒** (NFR Performance)。

### Q7-2. 同時利用ユーザ数は？
**50 ユーザ同時利用** (NFR Concurrency)。

### Q7-3. 可用性は？
**業務時間中 99%** (NFR Availability)。

### Q7-4. 多言語対応は？
**日本語 + ベトナム語** (i18n) — NFR Language。

### Q7-5. 対応ブラウザは？
Chrome / Edge / Firefox の **最新 2 バージョン** (NFR Browser)。

### Q7-6. バックアップは？
日次フルバックアップ、**30 日間保持** (NFR Backup)。

---

## 8. Master Data・Versioning

### Q8-1. Master Data の Versioning はどう機能しますか？
`effectiveFrom` / `effectiveTo` で期間管理。**Master を変更しても既存 Project は旧 Version を使い続け**、新規 Project のみ新 Version を使用 (FR-05.2)。

### Q8-2. Master Data の Import / Export は？
JSON 形式で Import / Export 可能 (FR-05.3)。

### Q8-3. Master Data の対象テーブルは？
- Productivity Norm (Customer / Internal)
- Density Rule (KVP / KLOC)
- Phase Ratio (NewDev / Modernization)
- Complex Rate
- Complexity LOC Range
- PR/BL 既定値

---

## 9. 監査・履歴 (Audit & History)

### Q9-1. 計算実行のログは残りますか？
はい。**入出力のスナップショット**を毎回保存 (FR-06.1)。

### Q9-2. Master 変更履歴は？
Admin 画面 `SC-015` で確認可能 (FR-06.2)。

---

## 10. リスク・未解決事項 (Open Issues)

### Q10-1. 仕様書で未確定の事項は？

| # | 内容 | 状態 |
|---|---|---|
| 1 | Method B 用の **画面複雑度別 LOC 平均値** | データセット 32 画面のサンプル統計値 (Normal: Median 717 LOC、Hard: Q3 1,480 LOC) を基に PM とベースライン確定が必要 |
| 2 | Report / Batch のバグ密度の complex breakdown | Base §3.3 / §3.4 が "Opp 依存" 記載のため、Normal Rate を fallback として使用 |
| 3 | Excel 大容量 Import 対応 | 5,000 行超は **Java Action 実装**が必要 (Mendix 標準 Microflow は不可) |
| 4 | Excel 出力テンプレート | SC-WBS-Mendix_Estimation_VN.xlsx の正式サンプルファイル入手要 |

---

## 11. 関連プロジェクト: Todo 管理システム

`/workspace/output/画面一覧.md` に別プロジェクトの資料があります。

### Q11-1. Todo 管理システムとは何ですか？
別途進行中の Mendix アプリ (`TodoManagementApp`)。**15 画面構成**の Todo / Category / Tag 管理システムで、`TodoManagement` と `TodoShared` の 2 モジュール構成です。

### Q11-2. Todo 管理システムの未確定事項は？
- コメント機能 (`Comment` entity) の独立画面 / Snippet 化判断
- 添付ファイルの最大サイズ・対応拡張子 (Constant `MAX_ATTACHMENT_SIZE_MB` / `ALLOWED_FILE_EXTENSIONS`)
- モバイル対応 (S-014, S-015) の必要性
- 通知機能 (期限超過・リマインダ) の要否

> 詳細な FAQ が必要な場合はお知らせください。

---

## 改訂履歴

| Ver | 日付 | 担当 | 内容 |
|---|---|---|---|
| 1.0 | 2026-05-26 | Laida-Mx | 初版作成 (EstimationTool_Specs.md / Base_of_estimation.md / 画面一覧.md を元に) |
