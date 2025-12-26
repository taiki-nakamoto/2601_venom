# GitHubリポジトリ作成

## 概要

このドキュメントでは、2601_venomプロジェクトをGitHubの新規リポジトリとして登録する手順を説明します。

## 前提条件

- GitHubアカウント: https://github.com/taiki-nakamoto
- Gitがインストールされていること
- プロジェクトディレクトリ: `/home/naka/claude_code/2601_venom`

## 手順1: GitHubでリポジトリを作成

1. ブラウザで https://github.com/taiki-nakamoto にアクセス
2. 右上の「+」→「New repository」をクリック
3. 以下を設定：
   - **Repository name**: `2601_venom` (または任意の名前)
   - **Description**: `Woodpecker CI + Venom integration testing with AWS`
   - **Public/Private**: お好みで選択
   - **Initialize this repository with**: 何もチェックしない（空のリポジトリとして作成）
4. 「Create repository」をクリック

## 手順2: ローカルでGitリポジトリを初期化

```bash
cd /home/naka/claude_code/2601_venom

# Gitリポジトリを初期化
git init

# デフォルトブランチをmainに設定
git branch -M main

# .gitignoreを確認（すでに作成済み）
cat .gitignore
```

## 手順3: 機密情報の除外を確認

コミット前に、機密情報が含まれていないか確認します：

```bash
# Terraformのステートファイルが存在しないか確認
find . -name "*.tfstate*" -o -name ".terraform"

# 除外されるファイルを確認
git status --ignored
```

### 除外されるべきファイル（.gitignoreで設定済み）

- `src/terraform/.terraform/` - Terraformプラグイン
- `src/terraform/terraform.tfstate*` - ステートファイル（機密情報含む）
- `src/terraform/*.tfvars` - 変数ファイル（機密情報含む可能性）
- `.env*` - 環境変数
- `*.pem`, `*.key` - 秘密鍵
- `secrets.txt`, `credentials.json` - 認証情報
- `src/woodpecker-data/` - Woodpecker永続データ

## 手順4: ファイルをステージング&コミット

```bash
# すべてのファイルを追加
git add .

# 追加されるファイルを確認
git status

# コミット
git commit -m "Initial commit: Woodpecker CI + Venom testing framework

- Add Terraform configuration for AWS infrastructure
- Add Woodpecker CI/CD pipeline with Venom integration
- Add documentation (検証プラン, AWS環境設計, EC2接続手順, Venom構築, DBサンプル)
- Add SQL schema and seed data
- Add API Gateway Mock configuration
- Add setup script for automated deployment"
```

## 手順5: リモートリポジトリを追加してプッシュ

```bash
# リモートリポジトリを追加（リポジトリ名を実際のものに置き換えてください）
git remote add origin https://github.com/taiki-nakamoto/2601_venom.git

# プッシュ
git push -u origin main
```

## 認証方法

GitHubの認証が必要な場合、以下のいずれかの方法を使用します。

### オプションA: Personal Access Token (PAT) を使用

```bash
# PATを使ってプッシュ
git push -u origin main
# Username: taiki-nakamoto
# Password: <Personal Access Token>
```

**PATの作成方法**:
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. 「Generate new token (classic)」をクリック
3. Note: `2601_venom repository access` など
4. Expiration: お好みで設定（90日推奨）
5. Select scopes: `repo` にチェック
6. 「Generate token」をクリック
7. トークンをコピー（この画面を閉じると二度と表示されません）
8. パスワード欄に貼り付け

### オプションB: SSH鍵を使用

```bash
# SSH URLに変更
git remote set-url origin git@github.com:taiki-nakamoto/2601_venom.git

# プッシュ
git push -u origin main
```

**SSH鍵の設定**:
1. SSH鍵を生成（まだ持っていない場合）
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```
2. 公開鍵をコピー
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```
3. GitHub → Settings → SSH and GPG keys → New SSH key
4. 公開鍵を貼り付けて保存

## 手順6: GitHubで確認

ブラウザでリポジトリを開き、以下が正しくアップロードされているか確認：

### コミットされるべきファイル

- ✅ `01_Document/` - ドキュメント6件
  - 01_Woodpecker検証プラン.md
  - 02_AWS環境設計.md
  - 03_EC2接続手順.md
  - 04_venom構築.md
  - 05_DBサンプル.md
  - 06_GitHubリポジトリ作成.md
- ✅ `02_Tasks/` - 次回作業予定
- ✅ `src/terraform/main.tf` - Terraformコード
- ✅ `src/.woodpecker.yml` - CIパイプライン定義
- ✅ `src/docker-compose.yml` - Woodpecker設定
- ✅ `src/setup.sh` - セットアップスクリプト
- ✅ `src/sql/` - SQLファイル
  - 01_schema.sql
  - 02_seed.sql
- ✅ `src/tests/` - Venomテスト
  - api_db_test.venom.yml
- ✅ `src/README.md` - 使い方ガイド
- ✅ `.gitignore` - 除外設定

### コミットされないファイル（.gitignore対象）

- ❌ `src/terraform/.terraform/`
- ❌ `src/terraform/terraform.tfstate*`
- ❌ `src/terraform/*.tfvars`
- ❌ `.env*`
- ❌ `*.pem`, `*.key`
- ❌ `secrets.txt`, `credentials.json`
- ❌ `src/woodpecker-data/`

## トラブルシューティング

### エラー: "Support for password authentication was removed"

HTTPSでプッシュ時にこのエラーが出る場合、Personal Access Tokenを使用してください（パスワードではなく）。

### エラー: "Permission denied (publickey)"

SSH接続時にこのエラーが出る場合：
1. SSH鍵が正しく設定されているか確認
   ```bash
   ssh -T git@github.com
   ```
2. GitHubに公開鍵が登録されているか確認

### リモートURLを確認・変更

```bash
# 現在のリモートURLを確認
git remote -v

# HTTPSからSSHに変更
git remote set-url origin git@github.com:taiki-nakamoto/2601_venom.git

# SSHからHTTPSに変更
git remote set-url origin https://github.com/taiki-nakamoto/2601_venom.git
```

## 今後の運用

### ブランチ戦略

本プロジェクトは検証用のため、シンプルな運用を推奨：

- `main` ブランチで直接作業
- 大きな変更の場合のみfeatureブランチを作成

### コミット時の注意

```bash
# 変更をステージング
git add <file>

# コミット
git commit -m "説明的なコミットメッセージ"

# プッシュ
git push origin main
```

### .gitignoreの更新

新しい機密情報や除外すべきファイルが発生した場合は、`.gitignore`を更新してください。

```bash
# .gitignoreを編集
vi .gitignore

# 変更をコミット
git add .gitignore
git commit -m "Update .gitignore"
git push origin main
```

## 参考資料

- [GitHub Docs - リポジトリを作成する](https://docs.github.com/ja/get-started/quickstart/create-a-repo)
- [GitHub Docs - Personal Access Token](https://docs.github.com/ja/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [GitHub Docs - SSH鍵の設定](https://docs.github.com/ja/authentication/connecting-to-github-with-ssh)
