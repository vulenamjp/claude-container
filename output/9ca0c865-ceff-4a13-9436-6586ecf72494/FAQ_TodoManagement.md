# FAQ — Todo 管理システム (TodoManagementApp)

**Version**: 1.0
**Date**: 2026-05-26
**対象資料**: `画面一覧.md` (Ver 0.1, 2026-05-25, 担当: namvl)
**関連 FAQ**: [FAQ.md](FAQ.md) — Mendix Estimation Tool

> 本 FAQ は **Todo 管理システム** (Mendix App: `TodoManagementApp`) の画面一覧資料を元に、よくある質問と回答をまとめたものです。

---

## 1. プロジェクト概要

### Q1-1. このアプリケーションは何ですか？
Mendix で構築する **Todo 管理システム** (`TodoManagementApp`) です。Todo タスクの作成・編集・完了管理に加え、Category (カテゴリ) と Tag (タグ) による分類管理を提供します。

### Q1-2. 対象範囲は？
ユーザが直接操作するすべての Mendix Page。Mendix 標準の `Login` ページは対象外です。

### Q1-3. どのプラットフォームをサポートしますか？
- **Web** (Atlas UI 3 / `Responsive_Main` レイアウト)
- **モバイル (任意)** — `Phone_Main` レイアウト (S-014, S-015)
- **Popup** — `Popup_Default` レイアウト (Select / 編集ダイアログ系)

### Q1-4. Mendix バージョンは？
画面一覧では未明示 (※要確認)。命名規約・widget 制約から **Mendix 11** 想定。

---

## 2. モジュール構成

### Q2-1. アプリは何モジュールで構成されますか？
**2 モジュール構成**です。

| Module 物理名 | 役割 |
|---|---|
| `TodoManagement` | Todo / Category / Tag 等の業務ドメイン |
| `TodoShared` | Snippet, 共通 Layout, 共通 Enumeration |

### Q2-2. なぜ Shared モジュールを分けるのですか？
Snippet / Layout / Enumeration 等の**横断的に利用される部品を集約**し、ドメインモジュールの依存方向を一方向にするためです (mx-cd-convention 準拠)。

---

## 3. ユーザロール・権限

### Q3-1. ユーザロール (Module Role) は？
2 種類。
- **EndUser** — 一般利用者
- **Administrator** — 管理者

### Q3-2. 一般ユーザ (EndUser) は他人の Todo を見られますか？
**いいえ。** EndUser は自分の Todo のみ閲覧可能。Administrator は全ユーザの Todo を閲覧可能 (画面一覧 §6)。

### Q3-3. Category / Tag は誰が管理しますか？
- **Administrator**: 作成・編集・削除すべて可能
- **EndUser**: 参照のみ (△)

### Q3-4. Administrator 専用画面は？
- `S-002` Home_Web_Administrator
- `S-008` Category_NewEdit
- `S-010` Tag_NewEdit
- `S-012` User_Overview
- `S-013` User_NewEdit

---

## 4. 画面 (Page) 一覧

### Q4-1. 全部で何画面ありますか？
**15 画面** (S-001 〜 S-015)。Web 13 画面 + モバイル 2 画面 (任意)。

### Q4-2. 画面の分類は？

| 区分 | 画面数 | S-ID |
|---|---:|---|
| ホーム / ダッシュボード | 2 | S-001, S-002 |
| Todo 関連 (Web) | 4 | S-003 〜 S-006 |
| マスタ管理 (Category / Tag) | 4 | S-007 〜 S-010 |
| ユーザ・アカウント | 3 | S-011 〜 S-013 |
| モバイル (任意) | 2 | S-014, S-015 |

### Q4-3. Todo の主要操作画面はどれですか？

| S-ID | Page 物理名 | 用途 |
|---|---|---|
| S-003 | `Todo_Overview` | 一覧 (検索・絞り込み) |
| S-004 | `Todo_NewEdit` | 新規作成・編集 |
| S-005 | `Todo_View` | 詳細表示 (read-only) |
| S-006 | `Todo_Select` | 他画面から Todo を選択するための Popup |

### Q4-4. Home 画面はロールで分かれていますか？
はい。
- `S-001` `Home_Web_EndUser` — 未完了 Todo 件数・本日期限 Todo を表示
- `S-002` `Home_Web_Administrator` — 全ユーザ Todo サマリ・Category 管理導線

### Q4-5. ユーザは自分のプロフィールを編集できますか？
はい。`S-011` `Account_Edit` で氏名・メール・パスワードを変更可能です。

---

## 5. 命名規約 (Naming Convention)

### Q5-1. Page の命名規則は？
`{Entity}_{Suffix}` 形式 (mx-cd-convention `page-ui` 準拠)。

| Suffix | 用途 |
|---|---|
| `_Overview` | 一覧 |
| `_NewEdit` | 新規 + 編集兼用 |
| `_View` | 詳細表示 (read-only) |
| `_Select` | 他画面から選択する Popup |

Home 画面のみ例外的に `Home_{Device}_{Role}` 形式 (例: `Home_Web_EndUser`)。

### Q5-2. モバイル画面の命名は？
`{Entity}_Phone_{Suffix}` 形式。例: `Todo_Phone_Overview`, `Todo_Phone_NewEdit`。

### Q5-3. Snippet の命名規則は？
`SNIP_{Name}` 形式。

| Snippet | 用途 |
|---|---|
| `SNIP_Todo_StatusBadge` | Todo の状態を色付きバッジで表示 |
| `SNIP_Todo_PriorityIcon` | 優先度アイコン表示 |
| `SNIP_Common_Pager` | ページャ (全 `_Overview` 系) |
| `SNIP_Common_ValidationMessages` | 入力検証メッセージ (全 NewEdit 系) |
| `SNIP_Common_Breadcrumb` | パンくずリスト |

### Q5-4. Microflow の命名は？
`{PREFIX}_{Entity}_{Operation}` 形式。`ACT_` Prefix が多用されています。

| Microflow | 用途 |
|---|---|
| `ACT_Todo_OpenOverview` | Todo 一覧画面を開く |
| `ACT_Todo_OpenNew` | Todo 新規作成画面を開く |
| `ACT_Todo_OpenView` | Todo 詳細画面を開く |
| `ACT_Todo_OpenEdit` | Todo 編集画面を開く |
| `ACT_Todo_Save` | Todo 保存 |
| `ACT_Todo_Cancel` | Todo 編集キャンセル |
| `ACT_Todo_Delete` | Todo 削除 |
| `ACT_Todo_MarkCompleted` | Todo 完了マーク |
| `ACT_Todo_ReturnSelected` | Select Popup から選択結果を返却 |
| `ACT_Category_OpenOverview` / `_OpenNewEdit` / `_Save` / `_Cancel` / `_Delete` | Category 操作 |
| `ACT_Tag_OpenNewEdit` / `_Save` / `_Cancel` / `_Delete` | Tag 操作 |
| `ACT_User_OpenOverview` / `_OpenNewEdit` / `_Save` / `_Cancel` / `_Deactivate` | User 操作 (管理者) |
| `ACT_Account_Save` / `_ChangePassword` | プロフィール操作 |
| `ACT_Comment_Add` | コメント追加 |

### Q5-5. Layout の命名は？
device prefix で識別 (mx-cd-convention 準拠)。

| Layout | 用途 |
|---|---|
| `Responsive_Main` | Web メイン Layout (Atlas UI 3) |
| `Phone_Main` | モバイル Layout |
| `Popup_Default` | Popup 用 Layout |

---

## 6. UI / Widget

### Q6-1. 使用してよい widget は？
画面設計書 §2.1.1 の許可 widget のみ使用 (画面一覧 §2 制約)。

### Q6-2. 使用禁止 widget は？
**`Dropdown` / `Reference Selector`** などの deprecated widget は不可。後継の widget を使用すること。

---

## 7. 共通機能 (Snippet)

### Q7-1. どのような共通 Snippet がありますか？
5 つ (画面一覧 §5)。
- `SNIP_Todo_StatusBadge` — 状態表示バッジ
- `SNIP_Todo_PriorityIcon` — 優先度アイコン
- `SNIP_Common_Pager` — ページャ
- `SNIP_Common_ValidationMessages` — 検証メッセージ
- `SNIP_Common_Breadcrumb` — パンくずリスト

### Q7-2. Snippet を使うメリットは？
**重複実装を排除し、見た目と動作の一貫性を保証**できます。Todo の状態バッジを全画面で同じスタイルにする等。

---

## 8. アクセス制御

### Q8-1. アクセス制御はどこで定義されますか？
- **画面レベル**: 画面一覧 §6 の Page アクセスマトリクス
- **エンティティレベル**: `06_テーブル定義書` / Mendix Access Rules で詳細定義

### Q8-2. EndUser が自分の Todo のみ見えるようにする仕組みは？
Entity Access Rule の **XPath 制約**で `[Todo_Owner = '[%CurrentUser%]']` を設定 (詳細は要確認、典型的な Mendix パターン)。

---

## 9. 未確定事項 (要確認)

### Q9-1. 仕様書で未確定の事項は？

| # | 内容 | アクション |
|---|---|---|
| 1 | コメント機能 (`Comment` entity) | 独立画面 / Snippet 内蔵かを要件確認 |
| 2 | 添付ファイル (`Attachment`) | 最大サイズ・対応拡張子。Constant `MAX_ATTACHMENT_SIZE_MB` / `ALLOWED_FILE_EXTENSIONS` で定義予定 |
| 3 | モバイル対応 (S-014, S-015) | ステークホルダーへ必要性確認 |
| 4 | 通知機能 (期限超過・リマインダ) | 別画面 (`Notification_Overview`) 要否を確認 |

### Q9-2. これらが確定するまでに何ができますか？
- Q9-1 #1 (コメント): Todo_View 内 Snippet (`SNIP_Todo_Comments`) として実装する想定で進め、独立画面が必要になったら切り出す
- Q9-1 #2 (添付): Constant のみ先に定義し、デフォルト値を `5 MB` / `.pdf,.jpg,.png,.docx,.xlsx` などで仮置き
- Q9-1 #3 (モバイル): 任意とし、Phase 2 リリース対象とする
- Q9-1 #4 (通知): Entity 設計だけ先行し、画面化はステークホルダー確認後

---

## 10. 関連ドキュメント

### Q10-1. このアプリの関連ドキュメントは？
画面一覧 §8 に記載:
- `04_画面設計書` — 各画面の項目仕様
- `05_画面遷移図`
- `06_テーブル定義書` — Todo / Category / Tag / User entity
- `10_業務ルール` — `BR-001` 「Todo 完了済みは編集不可」等
- `mx-cd-convention/page-ui` — 画面命名・widget 規約

### Q10-2. Mendix 命名規約はどこに準拠していますか？
**FPT LCG Team の `mx-cd-convention`** に準拠。Page / Layout / Snippet / Microflow / Entity / Attribute / Enumeration / Constant など、すべての物理名が同規約に従います。

---

## 11. 次のステップ

### Q11-1. 画面一覧の次に作成すべきドキュメントは？
依存関係を踏まえ、以下の順で作成推奨:
1. **テーブル定義書** (06) — Entity / Attribute 確定。XPath 等の前提
2. **画面設計書** (04) — 各画面の項目仕様 (Entity 参照)
3. **画面遷移図** (05) — Page 間遷移の Mermaid 図
4. **業務ルール** (10) — `BR-001` 等の業務制約
5. **処理ロジック設計書** (11) — Microflow の中身

### Q11-2. 業務ルールの例は？
- `BR-001`: Todo の Status が `Completed` の場合、編集不可
- (他は `10_業務ルール` で確定)

---

## 改訂履歴

| Ver | 日付 | 担当 | 内容 |
|---|---|---|---|
| 1.0 | 2026-05-26 | Laida-Mx | 初版作成 (画面一覧.md v0.1 を元に) |
