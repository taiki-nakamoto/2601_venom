# Venom検証テスト（応用編）

## 概要

このドキュメントでは、Venomを使ったデータベースとAPIの統合テストを実施します。

**前提条件**: 「07_動作確認テスト.md」の基本編を完了していること

**確認範囲**:
- Venom経由でのDB接続・データ投入テスト
- Venom経由でのAPI Gateway確認
- Woodpecker CI/CDパイプラインの統合テスト
- エンドツーエンド検証

## フェーズ1: Venomパイプラインの手動実行

### 1.1 手動ビルド実行

**目的**: Woodpecker UIから手動でパイプラインを起動し、Venomテストが正常に実行されることを確認

**手順**:
1. Woodpecker UI → リポジトリ → `2601_venom` を選択
2. 「Pipelines」タブをクリック
3. 「Trigger pipeline」または「New pipeline」をクリック
4. ブランチ: `main` を選択
5. 「Start pipeline」をクリック

**チェック項目**:
- [ ] パイプラインが開始される
- [ ] `setup-db` ステップが実行される
- [ ] `test` ステップが実行される
- [ ] 両方のステップが成功（緑色のチェックマーク）

**トラブルシューティング**:
- パイプラインが開始されない → リポジトリが有効化されているか確認
- ステップが見つからない → `.woodpecker.yml` がリポジトリのルートにあるか確認

### 1.2 setup-db ステップのログ確認

**目的**: SQLファイルが正常に実行され、テーブルとデータが作成されることを確認

Woodpecker UIで `setup-db` ステップのログを開き、以下を確認します。

**期待されるログ**:
```bash
+ export PGPASSWORD=password123
+ psql -h woodpecker-db-cluster.cluster-xxx.ap-northeast-1.rds.amazonaws.com -U postgres -d testdb -f sql/01_schema.sql
CREATE TABLE

+ psql -h woodpecker-db-cluster.cluster-xxx.ap-northeast-1.rds.amazonaws.com -U postgres -d testdb -f sql/02_seed.sql
INSERT 0 1
```

**チェック項目**:
- [ ] `CREATE TABLE` が表示される
- [ ] `INSERT 0 1` が表示される（1行挿入成功）
- [ ] エラーメッセージが表示されていない

**トラブルシューティング**:
- "could not connect to server" → Aurora DBが起動しているか確認（0.0 ACUの場合15-30秒待つ）
- "FATAL: password authentication failed" → `password123` が正しいか確認
- "permission denied" → Security Group（EC2→Aurora: ポート5432）を確認

### 1.3 test ステップのログ確認

**目的**: Venomテストが正常に実行され、すべてのアサーションがパスすることを確認

Woodpecker UIで `test` ステップのログを開き、以下を確認します。

**期待されるログ**:
```bash
+ venom run tests/*.venom.yml --var "db_url=postgres://postgres:password123@xxx:5432/testdb" --var "api_url=https://xxx.execute-api.ap-northeast-1.amazonaws.com/dev/users"

 • API Integration Test with Aurora (api_db_test.venom.yml)
  • Check API response after DB update SUCCESS

Tests Summary:
  Total: 1
  Passed: 1
  Failed: 0
  Skipped: 0
```

**チェック項目**:
- [ ] Venomテストが実行される
- [ ] `SUCCESS` が表示される
- [ ] `Passed: 1, Failed: 0` が表示される
- [ ] アサーションがすべてパスする

**トラブルシューティング**:
- "FAILED" が表示される → 詳細なエラーメッセージを確認
- DB接続エラー → `db_url` の環境変数が正しいか確認
- API接続エラー → `api_url` の環境変数が正しいか確認
- アサーション失敗 → API Gatewayのレスポンスを確認

## フェーズ2: 各ステップの詳細検証

### 2.1 DBテーブルとデータの確認

**目的**: setup-dbステップで作成されたテーブルとデータが正しいことを確認

EC2にSSHで接続し、以下を実行：

```bash
# 環境変数設定
export PGPASSWORD=password123
export DB_ENDPOINT=<Terraform出力のdb_endpoint>

# テーブル一覧確認
psql -h $DB_ENDPOINT -U postgres -d testdb -c "\dt"

# データ確認
psql -h $DB_ENDPOINT -U postgres -d testdb -c "SELECT * FROM users;"
```

**期待される出力**:
```
         List of relations
 Schema | Name  | Type  |  Owner
--------+-------+-------+----------
 public | users | table | postgres

 id  |   username   |      email       |   address    | status   | created_by   | ...
-----+--------------+------------------+--------------+----------+--------------+-----
 100 | test_user_01 | test@example.com | Tokyo, Japan | inactive | setup_script | ...
```

**チェック項目**:
- [ ] `users` テーブルが存在する
- [ ] ID 100のユーザーデータが存在する
- [ ] `status` が `inactive` になっている（初期値）

### 2.2 Venomによるデータ更新の確認

**目的**: VenomテストでDBが更新されることを確認

Venomテストでは以下のSQL（`tests/api_db_test.venom.yml`）が実行されます：

```yaml
- type: dbfixtures
  database: postgres
  dsn: "{{.db_url}}"
  commands:
    - "UPDATE users SET status = 'active', updated_by = 'venom_test' WHERE id = 100;"
```

**パイプライン実行後に確認**:

```bash
# Venomテスト実行後のデータ確認
psql -h $DB_ENDPOINT -U postgres -d testdb -c "SELECT id, status, updated_by FROM users WHERE id = 100;"
```

**期待される出力**:
```
 id  | status | updated_by
-----+--------+------------
 100 | active | venom_test
```

**チェック項目**:
- [ ] `status` が `active` に更新されている
- [ ] `updated_by` が `venom_test` に更新されている

### 2.3 API Gatewayレスポンスの確認

**目的**: API Gateway Mockが正しいレスポンスを返すことを確認

```bash
# 環境変数設定
export API_URL=<Terraform出力のapi_gateway_url>

# API呼び出し
curl -X GET "${API_URL}/100"

# 整形して表示（jqがある場合）
curl -X GET "${API_URL}/100" | jq .
```

**期待されるレスポンス**:
```json
{
  "id": 100,
  "username": "test_user_01",
  "email": "test@example.com",
  "address": "Tokyo, Japan",
  "status": "active",
  "created_by": "setup_script",
  "updated_by": "venom_test"
}
```

**チェック項目**:
- [ ] HTTPステータス 200が返る
- [ ] JSONレスポンスが返る
- [ ] `status: "active"` が含まれる
- [ ] `updated_by: "venom_test"` が含まれる

**重要な注意**:
現在のAPI Gateway Mock設定では、**固定のレスポンス**を返します。実際のDB値は反映されません。

## フェーズ3: エンドツーエンド検証

### 3.1 コード変更によるパイプライン自動実行

**目的**: GitHubへのpushでWoodpeckerパイプラインが自動実行されることを確認

```bash
# EC2上で作業
cd ~/2601_venom

# Gitユーザー設定（初回のみ）
git config --global user.email "you@example.com"
git config --global user.name "Your Name"

# テストファイルを修正（コメント追加）
echo "" >> tests/api_db_test.venom.yml
echo "# Test: Auto trigger $(date)" >> tests/api_db_test.venom.yml

# 変更を確認
git diff tests/api_db_test.venom.yml

# コミット
git add tests/api_db_test.venom.yml
git commit -m "Test: Trigger auto pipeline"

# プッシュ
git push origin main
# Username: taiki-nakamoto
# Password: <Personal Access Tokenを貼り付け>
```

**チェック項目**:
- [ ] GitHubへのpushが成功する
- [ ] Woodpecker UIで自動的に新しいパイプラインが開始される
- [ ] setup-db → test の順に実行される
- [ ] すべてのステップが成功する

**トラブルシューティング**:
- パイプラインが自動実行されない → Webhookが設定されているか確認（通常は自動）
- "Authentication failed" → Personal Access Tokenを確認

### 3.2 複数回実行の冪等性確認

**目的**: 同じパイプラインを複数回実行しても問題ないことを確認

Woodpecker UIで「Restart」ボタンをクリックし、同じパイプラインを再実行します。

**チェック項目**:
- [ ] 2回目の実行も成功する
- [ ] `CREATE TABLE IF NOT EXISTS` により、テーブル作成がスキップされる
- [ ] `ON CONFLICT` により、データ挿入が適切に処理される

**期待される動作**:
- テーブルが既に存在する場合、エラーにならない
- データが既に存在する場合、`ON CONFLICT` により適切に処理される

### 3.3 完全なフローの確認

**目的**: DB準備 → データ更新 → API確認の一連の流れが正常に動作することを確認

**完全なフロー**:
1. **setup-db**: SQLファイルでテーブル作成とシードデータ投入
2. **test/dbfixtures**: Venomでステータスを更新（inactive → active）
3. **test/http**: VenomでAPI Gatewayを呼び出してレスポンス確認

**チェック項目**:
- [ ] 各ステップが順番に実行される
- [ ] データの状態が各ステップで正しく変化する
- [ ] 最終的にすべてのアサーションがパスする

## フェーズ4: テストケースの追加（オプション）

### 4.1 異常系テストの追加

**目的**: 存在しないユーザーへのアクセスで404が返ることを確認

現在のVenomテストには以下の異常系テストが含まれています：

```yaml
# ステップ3: 異常系のテスト（例：存在しないユーザー）
- type: http
  method: GET
  url: "{{.api_url}}/users/999"
  assertions:
    - result.statuscode ShouldEqual 404
```

**注意**:
現在のAPI Gateway Mock設定では、すべてのIDに対して200を返すため、**このテストは失敗します**。

**対応方法**:
- テストから404のチェックを削除する
- または、Lambda統合に変更して動的なレスポンスを返すようにする

### 4.2 テストケースの編集

異常系テストを削除する場合：

```bash
cd ~/2601_venom
vi tests/api_db_test.venom.yml
```

以下のセクションを削除またはコメントアウト：

```yaml
      # ステップ3: 異常系のテスト（例：存在しないユーザー）
      # - type: http
      #   method: GET
      #   url: "{{.api_url}}/users/999"
      #   assertions:
      #     - result.statuscode ShouldEqual 404
```

保存後、コミット＆プッシュして再度テスト実行します。

## 検証完了チェックリスト

### 全体確認

- [ ] フェーズ1: Venomパイプラインの手動実行 → すべてクリア
- [ ] フェーズ2: 各ステップの詳細検証 → すべてクリア
- [ ] フェーズ3: エンドツーエンド検証 → すべてクリア
- [ ] フェーズ4: テストケースの追加（オプション） → 必要に応じて実施

### 検証ゴールの達成確認

以下の4つのゴールがすべて達成されたことを確認：

- [ ] **インフラ構築**: Terraform でVPC、EC2、Auroraが正しく作成される
- [ ] **CI基盤**: Woodpeckerが起動し、GitHubと連携できる
- [ ] **DB連携**: Woodpeckerから`setup-db`ステップでAuroraにSQLを実行できる
- [ ] **Venomテスト**: `test`ステップでVenomがDBを更新し、API（Mock）を呼び出せる

## 検証後の作業

### 成果物の記録

以下をスクリーンショットまたはログとして保存：

- [ ] Terraform出力結果
- [ ] Woodpecker UIのパイプライン成功画面
- [ ] setup-dbステップのログ
- [ ] testステップのログ（Venom実行結果）
- [ ] DBのSELECT結果（更新前/更新後）
- [ ] API Gatewayのレスポンス

### 検証レポート作成

`03_Research/` ディレクトリに検証結果をまとめる：

```bash
cd ~/2601_venom/03_Research
vi YYYYMMDD_01_検証結果レポート.md
```

**記載内容**:
- 検証日時
- 検証環境（リージョン、インスタンスタイプ、AMI ID等）
- 各フェーズの結果（成功/失敗）
- 発生した問題と解決方法
- API Gateway Mockの制限事項
- 所感・改善点
- 次のステップ（Lambda統合など）

### リソースのクリーンアップ

検証完了後、コスト削減のためリソースを削除：

```bash
# ローカルPC（Terraformを実行した環境）で実行
cd /home/naka/claude_code/2601_venom/src/terraform
terraform destroy
```

**確認事項**:
- [ ] 削除前にスクリーンショット・ログを保存済み
- [ ] GitHubリポジトリにコードがpush済み
- [ ] 検証レポートを作成済み
- [ ] `yes` を入力してリソースを削除

**削除されるリソース**:
- VPC（サブネット、ルートテーブル、Internet Gateway含む）
- EC2インスタンス（Elastic IP含む）
- Aurora Serverless v2クラスター
- API Gateway
- Security Group

## 今後の改善案

### Lambda統合への移行

現在のAPI Gateway Mockは固定レスポンスですが、Lambda統合により以下が実現できます：

**メリット**:
- 実際のDB値を取得してレスポンスを返せる
- パスパラメータ（ID）に応じた動的なレスポンス
- 存在しないIDに対して404を返せる
- より本番に近い検証が可能

**実装の概要**:
1. Lambda関数を作成（Python/Node.js）
2. Aurora接続設定（VPC Lambda）
3. API GatewayとLambdaの統合
4. Venomテストの404チェックを有効化

詳細は別途ドキュメント化を検討してください。

## 参考資料

- `01_Woodpecker検証プラン.md` - 検証の全体像
- `04_venom構築.md` - Venom構築手順
- `05_DBサンプル.md` - DBテーブル設計
- `07_動作確認テスト.md` - 基本編（前提条件）
- `src/README.md` - トラブルシューティング詳細
- `src/.woodpecker.yml` - パイプライン定義
- `src/tests/api_db_test.venom.yml` - Venomテスト定義
