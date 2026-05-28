# FAQ — Mendix 見積りベース（Base of Estimation）

出典：`Base_of_estimation.md`（元ファイル：`SC-WBS-Mendix_Estimation_VN.xlsx` シート `#Base_of_estimation`）

本FAQは、見積りを行うメンバー／レビュアー向けに、資料の数値・ルール・適用方法を素早く参照できるようにまとめたものです。

---

## 1. 基本単位・換算ルール

### Q1-1. KLOC、VP、KVP の関係は？
- **1 KLOC = 1,000 LOC**
- **1 VP = 1.6 Step**
- **1 KVP = 1.6 KLOC**

LOC ベースの数値と VP ベースの数値を相互変換する際は、必ず `1 KVP = 1.6 KLOC` の係数を使用してください。

### Q1-2. 「Bản khách hàng」と「Bản internal」の違いは？
- **Bản khách hàng（顧客提出用）**：顧客に提示する数値。SI 見積りで使用。
- **Bản internal（社内用 / Java・.Net）**：社内の参考用。**顧客に提出する前に必ず削除**してください（資料 0.1 節）。

> Internal 用テーブル（cột O〜Z）は値だけコピーし、関連計算式を残さないこと。

---

## 2. 生産性（Productivity）

### Q2-1. 顧客提出用の標準生産性（New 開発）は？

| 工程 | screen (online) | batch | report | 単位 |
|------|---:|---:|---:|---|
| REQ（要件定義） | 3.5 | 3.5 | 3.5 | Page/MD |
| BD（基本設計） | 5 | 5 | 5 | Page/MD |
| DD（詳細設計） | 6 | 6 | 6 | Page/MD |
| CD（コーディング） | 180 | 190 | 190 | VP/MD |
| UT 作成 | 60 | 60 | 60 | Case/MD |
| UT 実行 ※ | 60 | 60 | 60 | Case/MD |
| UT バグ対応 | 12 | 12 | 12 | Request/MD |
| IT 作成 | 40 | 30 | 40 | Case/MD |
| IT 実行 ※ | 40 | 30 | 40 | Case/MD |
| IT バグ対応 | 6 | 6 | 6 | Request/MD |
| ST 作成 | 25 | 25 | 30 | Case/MD |
| ST 実行 ※ | 20 | 20 | 20 | Case/MD |
| ST バグ対応 | 3 | 3 | 3 | Request/MD |

※ Manual test（Black box test）、evidence 取得工数を含む。

### Q2-2. 生産性は調整して良いですか？
- **可**。新規開発 Java/.Net 向けの Norm 値です。
- 顧客が end user である場合などは **下方修正可**。
- ただし overhead 工数は **含まれていません**（別途加算が必要）。

### Q2-3. 「Năng suất tổng hợp（SUM）」とは？

工程レンジ別の合計生産性（KLOC/人月）。

| Phase range | online | batch | report |
|---|---:|---:|---:|
| REQ 〜 ST | 0.889 | 1.105 | 0.995 |
| BD 〜 IT | 1.188 | 1.435 | 1.290 |
| DD 〜 UT | 1.739 | 2.034 | 1.875 |

スコープ範囲が決まっている場合、KLOC を上記で割って人月を概算できます。

---

## 3. 密度（Density）

### Q3-1. ページ密度・テストケース密度（顧客提出用、By KVP）

| 工程 | screen | batch | report | 単位 |
|---|---:|---:|---:|---|
| REQ | 9.6 | 8 | 8 | Page/KVP |
| BD | 16 | 16 | 16 | Page/KVP |
| DD | 32 | 24 | 24 | Page/KVP |
| UT Case | 112 | 110 | 120 | Case/KVP |
| UT Bug | 10 | 8 | 7 | Bug/KVP |
| IT Case | 64 | 22.4 | 48 | Case/KVP |
| IT Bug | 5 | 4 | 3 | Bug/KVP |
| ST Case | 32 | 16 | 25.6 | Case/KVP |
| ST Bug | 2.24 | 1.12 | 1.68 | Bug/KVP |

### Q3-2. By KLOC への換算は？
`1 KVP = 1.6 KLOC` で割る。例：BD = 16 Page/KVP ÷ 1.6 = **10 Page/KLOC**。

---

## 4. 工程間の比率

### Q4-1. 新規開発（New Development）の工程比率は？

> **これは標準比率で、変更不可。**

| 工程 | 比率 |
|---|---:|
| BD | 0.167 |
| DD | 0.175 |
| CD / UT | 0.355 |
| IT | 0.173 |
| ST | 0.130 |
| **Total** | **1.000** |

### Q4-2. 再開発（Modernization / Replace / Migration）の工程比率は？

Base = **製作（CD + UT）= 100**。各工程は製作工数に対する % で算出。

| 工程 | % vs 製作 | % vs Total |
|---|---:|---:|
| 要件定義（REQ） | 17.2 % | 5.2 % |
| 基本設計（BD） | 52.5 % | 15.8 % |
| 詳細設計（DD） | 48.8 % | 14.7 % |
| 製作（CD + UT） | 100.0 % | 30.2 % |
| 結合テスト（IT） | 49.2 % | 14.8 % |
| 総合テスト（ST） | 63.9 % | 19.3 % |
| **Total** | **331.6 %** | **100.0 %** |

### Q4-3. 製作（CD + UT）を CD と UT に分けたい場合は？
**50 / 50** で分割（生産性は同等とみなす）。
- CD：製作 × 0.5（全体の 15.1 %）
- UT：製作 × 0.5（全体の 15.1 %）

### Q4-4. 製作工数から他工程の工数を算出する式は？

```
Effort_REQ = Effort_製作 × 0.172
Effort_BD  = Effort_製作 × 0.525
Effort_DD  = Effort_製作 × 0.488
Effort_IT  = Effort_製作 × 0.492
Effort_ST  = Effort_製作 × 0.639
Effort_CD  = Effort_UT = Effort_製作 × 0.5
Effort_Total (REQ〜ST) = Effort_製作 × 3.316
```

---

## 5. 複雑度（Complexity）

### Q5-1. Complex Rate の標準値は？

| Complex type | Rate |
|---|---:|
| Very easy | 0.8 |
| Easy | 0.8 |
| Normal | 1.0 |
| Hard | 1.2 |
| Very hard | 1.4 |

> 注意：画面テーブルの「Complex Rate」列では Easy = 0.9 と表記されている箇所がありますが、本 FAQ の集計は **計算式参照元の P/Q 列（Easy = 0.8）** を採用しています。

### Q5-2. 画面の複雑度はどう判定する？（View point：Data table）

| 複雑度 | Data table 数 | Rate | 代表例 |
|---|:---:|---:|---|
| Very easy | < 2 | 0.8 | 共通 Excel ダウンロード機能 / 計算なしの単純照会 |
| Easy | 2 | 0.9 | 計算ありリスト照会 / 単純アイコンメニュー / 業務メインロジックなし |
| Normal | 3 | 1.0 | テーブル列変更・追加 / 重要業務ロジックあり / ソート・ページング機能 |
| Hard | 4 | 1.2 | データアップロード処理 / 重要業務ロジック含むバリデーション |
| Very hard | > 4 | 1.4 | OPEN API 連携 / 外部機器連携 / セキュリティ・暗号化モジュール / デバイスアプリ実装 |

### Q5-3. Report と Batch の複雑度は？
資料上は **Opp ごとに定義** と記載されています（Very easy 〜 Very hard の数値ガイドはなし）。プロジェクト固有で基準を決めてください。

### Q5-4. LOC ベースで複雑度を判定する場合は？

実 LOC（PR + BL）が分かる場合は、こちらを優先（資料 3.5 節、n=32 の実績）。

| 複雑度 | 総 LOC (PR + BL) | Rate | 例 |
|---|---|---:|---|
| Very easy | < 200 | 0.8 | 閉局画面、エラー画面の小規模 |
| Easy | 200 〜 800 | 0.8 | フォーム単純、ログイン、エラー、簡易 file download |
| Normal | 800 〜 2,000 | 1.0 | TOP、検索・リスト基本、パスワード変更、アカウント設定 |
| Hard | 2,000 〜 8,000 | 1.2 | 入力・アップロード複雑、業務ロジック付き redirect、多段画面 |
| Very hard | ≥ 8,000 | 1.4 | 確認画面（多ブロック）、申込内容選択（multi-product/tier）、画面別設定 |

### Q5-5. LOC 分布の参考値（n=32）

| 区分 | LOC |
|---|---:|
| Min | 29 |
| Q1 | 387 |
| Median | 717 |
| Q3 | 1,480 |
| Max | 25,548 |

---

## 6. PR層 / BL層 比率（フロントエンド / バックエンド）

### Q6-1. PR層 / BL層 とは？
- **PR層 (Presentation)**：UI、画面、クライアント側バリデーション
- **BL層 (Business Logic + Data Access)**：マイクロフロー、サービス、DB アクセス

### Q6-2. 画面単位の標準比率は？（共通モジュール除く）

| 層 | LOC | 比率 |
|---|---:|---:|
| PR層 (FE) | 27,659 | **38.9 %** |
| BL層 (BE) | 43,439 | **61.1 %** |
| Total | 71,098 | 100 % |

換算式：`Total_製作 = PR × 2.57` （または `BL = PR × 1.57`）

### Q6-3. プロジェクト全体の比率は？（共通モジュール含む）

| 層 | LOC | 比率 |
|---|---:|---:|
| PR層 | 40,197 | 22.1 % |
| BL層 | 141,431 | 77.9 % |
| Total | 181,628 | 100 % |

> 共通モジュールは master logic、認証、セッション、共通 API など **BL層が大半** を占めるため、画面単位の比率とは大きく異なります。

### Q6-4. 画面種別ごとの典型的な PR% は？

| 画面種別 | PR% | 補足 |
|---|---:|---|
| Output-only / consent / 閉局 | 100 % | BL なし（render のみ） |
| Error / Maintenance | 40 〜 50 % | 軽い routing logic |
| Login / Password / TOP | 20 〜 35 % | 認証・セッションが BL の大半 |
| Search / List | 25 〜 35 % | Query / paging / sorting が BL |
| Form input（単純） | 35 〜 50 % | Validation + 永続化 |
| Form input（複雑、multi-step、申込） | 50 〜 55 % | UI ロジック重め（条件付き render、dynamic） |
| Confirm / Display 集計 | 20 〜 25 % | BL 集計が大半 |

### Q6-5. プロジェクトプロファイル別の PR% デフォルトは？

- UI 重視（SPA、dynamic form）：PR% ≈ **50 %**
- バランス型（典型的 Web app）：PR% ≈ **40 %** ← **default**
- BL 重視（data-heavy、integration）：PR% ≈ **25 〜 30 %**

---

## 7. 適用上の注意

### Q7-1. 顧客提出前のチェックリスト
1. Internal 用テーブル（cột O〜Z）を削除済か。
2. 計算式が Internal テーブルに依存していないか（値コピーに変更済か）。
3. 生産性に overhead が考慮されているか（資料の Norm 値は overhead 未含み）。
4. 工程比率（Q4-1 / Q4-2）が新規／再開発のどちらに該当するか明示しているか。

### Q7-2. 数値の優先順位（迷ったとき）
1. **実 LOC データがある** → Q5-4 の LOC 区分を優先。
2. **画面 item 数のみ分かる** → Q5-2 の Data table ベース。
3. **製作工数のみ算出可能** → Q4-4 の比率式で他工程を算出。
4. **スコープ範囲が固定** → Q2-3 の SUM 生産性で人月概算。

### Q7-3. 本資料に書かれていないもの
- Overhead 工数の係数（プロジェクトごとに別途定義が必要）
- Report / Batch 複雑度の具体数値（Opp 単位で定義）
- 移行・データクレンジング工数
- 教育・引継ぎ工数

これらは見積り時に **別途加算項目** として明示してください。

---

## 参考

- 原典：`Base_of_estimation.md`（`SC-WBS-Mendix_Estimation_VN.xlsx` → `#Base_of_estimation`）
- 関連規約：`mx-cd-convention`（Mendix 物理名命名規約、見積り対象モジュール構成の前提）
