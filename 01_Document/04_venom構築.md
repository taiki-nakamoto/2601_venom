# Venom構築

## フェーズ1・2を一気に立ち上げるための最短テンプレート

Venomの最大の特徴は、**一つのYAMLファイル内で「DB操作」と「HTTPリクエスト」を順番に実行できる点**です。数時間のテストに最適な、シンプルかつ強力な構成になっています。

SQLファイルを専用フォルダに分離することで、可読性と保守性が向上しています。

> **詳細な使い方とトラブルシューティング**: `src/README.md` を参照してください

## ディレクトリ構成

```
src/
├── .woodpecker.yml          # CI/CDパイプライン定義
├── docker-compose.yml       # Woodpecker設定
├── setup.sh                 # 自動セットアップスクリプト
├── sql/                     # SQLスクリプト
│   ├── 01_schema.sql        # DDL（テーブル作成）
│   └── 02_seed.sql          # DML（初期データ投入）
└── tests/                   # テスト定義
    └── api_db_test.venom.yml # APIテスト
```

## 1. Woodpeckerサーバー構築用：docker-compose.yml

まずはEC2上でWoodpeckerを動かすための設定です。数時間のみの使い捨てを想定し、DBはSQLite、SSLなしのHTTP（ポート8000）で構成します。

```yaml
services:
  woodpecker-server:
    image: woodpeckerci/woodpecker-server:latest
    ports:
      - "8000:8000"
    volumes:
      - ./woodpecker-data:/var/lib/woodpecker/
    environment:
      - WOODPECKER_OPEN=true
      - WOODPECKER_HOST=http://[あなたのEC2パブリックIP]:8000
      - WOODPECKER_GITHUB=true
      - WOODPECKER_GITHUB_CLIENT=[GitHubのClient ID]
      - WOODPECKER_GITHUB_SECRET=[GitHubのClient Secret]
      - WOODPECKER_AGENT_SECRET=secret-token

  woodpecker-agent:
    image: woodpeckerci/woodpecker-agent:latest
    command: agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WOODPECKER_SERVER=woodpecker-server:9000
      - WOODPECKER_AGENT_SECRET=secret-token
```

## 2. SQLファイル

### sql/01_schema.sql - テーブル作成（DDL）

```sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    address TEXT,
    status VARCHAR(20) DEFAULT 'active',
    created_by VARCHAR(50),
    created_at TIMESTAMP DEFAULT now(),
    updated_by VARCHAR(50),
    updated_at TIMESTAMP DEFAULT now()
);
```

### sql/02_seed.sql - 初期データ投入（DML）

```sql
INSERT INTO users (id, username, email, address, status, created_by, updated_by)
VALUES (100, 'test_user_01', 'test@example.com', 'Tokyo, Japan', 'inactive', 'setup_script', 'setup_script')
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status;
```

## 3. CIパイプライン設定：.woodpecker.yml

リポジトリのルートに配置します。**2段階構成**でDBセットアップとテストを分離しています。

```yaml
pipeline:
  setup-db:
    image: postgres:16 # psqlコマンドを使用
    commands:
      # PGPASSWORD環境変数を使ってパスワードを指定し、SQLファイルを実行
      - export PGPASSWORD=password123
      - psql -h ${DB_ENDPOINT} -U postgres -d testdb -f sql/01_schema.sql
      - psql -h ${DB_ENDPOINT} -U postgres -d testdb -f sql/02_seed.sql
    environment:
      - DB_ENDPOINT=aurora-endpoint # 実際のエンドポイントに置き換える

  test:
    image: ovhcom/venom:latest
    commands:
      # Venomを実行。-varでDBの接続先などを動的に渡せます
      - venom run tests/*.venom.yml --var "db_url=postgres://postgres:password123@${DB_ENDPOINT}:5432/testdb" --var "api_url=https://[api-id].execute-api.ap-northeast-1.amazonaws.com/dev"
    environment:
      - DB_ENDPOINT=aurora-endpoint # 実際のエンドポイントに置き換える
```

## 4. Venomテスト定義：tests/api_db_test.venom.yml

これが今回の検証の核となるファイルです。「DBを書き換え → API Gatewayを叩く」の流れを記述します。

**テーブル作成とシードデータは `setup-db` ステップで完了済み**のため、テストではDB更新とAPI検証のみに集中できます。

```yaml
name: API Integration Test with Aurora
vars:
  api_url: "https://fallback-url.com" # --var で上書き可能
  db_url: "postgres://postgres:password123@localhost:5432/testdb"

testcases:
  - name: Check API response after DB update
    steps:
      # ステップ1: Auroraのデータを書き換える
      - type: dbfixtures
        database: postgres
        dsn: "{{.db_url}}"
        commands:
          - "UPDATE users SET status = 'active', updated_by = 'venom_test' WHERE id = 100;"

      # ステップ2: API Gateway (Mock) を叩く
      - type: http
        method: GET
        url: "{{.api_url}}/users/100"
        assertions:
          - result.statuscode ShouldEqual 200
          - result.bodyjson.id ShouldEqual 100
          - result.bodyjson.status ShouldEqual "active"
          - result.bodyjson.updated_by ShouldEqual "venom_test"

      # ステップ3: 異常系のテスト（例：存在しないユーザー）
      - type: http
        method: GET
        url: "{{.api_url}}/users/999"
        assertions:
          - result.statuscode ShouldEqual 404
```

## 5. パイプラインの実行フロー

1. **setup-db ステップ**:
   - PostgreSQL 16イメージでpsqlコマンドを実行
   - `sql/01_schema.sql`: usersテーブルを作成
   - `sql/02_seed.sql`: テストユーザー（ID: 100）を投入

2. **test ステップ**:
   - Venomイメージで統合テストを実行
   - DBのステータスを更新（inactive → active）
   - APIを呼び出してレスポンスを検証

## 6. この構成で検証できること

1. **Woodpeckerの基本動作**: GitHubへのPushに応じて、EC2上のAgentがジョブを拾うか
2. **Venomの操作性**: YAMLの記述だけでDBとAPIの両方をテストできる便利さの体感
3. **ネットワーク疎通**: EC2（CIエージェント）から、パブリックのAPI Gatewayと、プライベートのAuroraの両方にアクセスできるか
4. **SQLファイル分離のメリット**: DDL/DMLを独立管理し、テストコードがシンプルになることを確認

## 7. 構築手順

詳細な手順、トラブルシューティング、カスタマイズ方法については、**`src/README.md`** を参照してください。
