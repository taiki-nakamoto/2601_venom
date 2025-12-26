# Woodpecker + Venom テスト環境

## ディレクトリ構成

```
.
├── .woodpecker.yml          # CI/CDパイプライン定義
├── docker-compose.yml       # Woodpeckerサーバー/エージェント設定
├── setup.sh                 # 自動セットアップスクリプト
├── sql/                     # データベーススクリプト
│   ├── 01_schema.sql        # DDL: テーブル作成
│   └── 02_seed.sql          # DML: 初期データ投入
├── terraform/               # インフラ構築
│   └── main.tf              # AWS環境構築スクリプト
└── tests/                   # テストスクリプト
    └── api_db_test.venom.yml # APIテスト定義
```

## ファイルの役割

### sql/01_schema.sql
- **役割**: データベーステーブルの定義（DDL）
- **内容**: usersテーブルの作成
- **実行タイミング**: Woodpeckerの `setup-db` ステップで自動実行

### sql/02_seed.sql
- **役割**: テスト用初期データの投入（DML）
- **内容**: テストユーザー（ID: 100）の登録
- **特徴**: `ON CONFLICT` を使用しており、複数回実行可能

### .woodpecker.yml
- **役割**: CI/CDパイプラインの定義
- **構成**:
  1. `setup-db`: PostgreSQLクライアントでSQLファイルを実行
  2. `test`: Venomテストを実行

### tests/api_db_test.venom.yml
- **役割**: APIとDBの統合テスト
- **内容**:
  - DB更新（ステータス変更）
  - API呼び出し
  - レスポンス検証

## 使い方

### 1. Terraform で AWS環境を構築

```bash
cd terraform
terraform init
terraform apply
```

出力される `woodpecker_public_ip` と `db_endpoint` をメモしてください。

### 2. EC2にログインして自動セットアップ

```bash
# setup.sh を実行（対話式で必要な情報を入力）
./setup.sh
```

必要な情報：
- EC2 Public IP
- GitHub Client ID
- GitHub Client Secret
- Aurora Endpoint
- API Gateway URL

### 3. GitHubリポジトリに配置

以下のファイルをGitHubリポジトリにコミット：

```bash
git add .woodpecker.yml sql/ tests/
git commit -m "Add Woodpecker CI configuration"
git push
```

### 4. Woodpecker UI で確認

ブラウザで `http://<EC2 Public IP>:8000` にアクセスし、リポジトリを有効化します。

## パイプラインの流れ

1. **setup-db ステップ**:
   - PostgreSQL 16イメージを使用
   - `sql/01_schema.sql` を実行してテーブルを作成
   - `sql/02_seed.sql` を実行して初期データを投入

2. **test ステップ**:
   - Venomイメージを使用
   - `tests/api_db_test.venom.yml` を実行
   - DBを更新し、APIレスポンスを検証

## カスタマイズ

### SQLファイルを追加する場合

1. `sql/` ディレクトリに新しいファイルを追加（例: `03_additional_tables.sql`）
2. `.woodpecker.yml` の `setup-db` ステップに実行コマンドを追加：
   ```yaml
   - psql -h ${DB_ENDPOINT} -U postgres -d testdb -f sql/03_additional_tables.sql
   ```

### テストケースを追加する場合

1. `tests/` ディレクトリに新しいVenomファイルを追加
2. `.woodpecker.yml` は `tests/*.venom.yml` を実行するため、自動的に認識されます

## トラブルシューティング

### DB接続エラー

- Security Groupの設定を確認（EC2 → Aurora: ポート5432）
- Auroraのエンドポイントが正しいか確認
- 0.0 ACUの場合、起動に15〜30秒かかることに注意

### Woodpeckerが起動しない

```bash
# Dockerの状態を確認
docker ps

# ログを確認
docker-compose logs woodpecker-server
docker-compose logs woodpecker-agent
```

### テストが失敗する

```bash
# Venomのログで詳細を確認
# Woodpecker UIのログビューアで各ステップの出力を確認
```
