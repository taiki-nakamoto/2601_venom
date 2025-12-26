#!/bin/bash

echo "=== Woodpecker CI Setup Script ==="

# 1. 必要な情報の入力
read -p "Enter EC2 Public IP: " PUBLIC_IP
read -p "Enter GitHub Client ID: " GH_CLIENT_ID
read -p "Enter GitHub Client Secret: " GH_SECRET
read -p "Enter Aurora Endpoint: " DB_ENDPOINT
read -p "Enter API Gateway URL (Mock): " API_URL

# 作業ディレクトリの作成
mkdir -p ~/woodpecker-test/tests
cd ~/woodpecker-test

# 2. docker-compose.yml の作成
cat << EOC > docker-compose.yml
services:
  woodpecker-server:
    image: woodpeckerci/woodpecker-server:latest
    ports:
      - "8000:8000"
    volumes:
      - ./woodpecker-data:/var/lib/woodpecker/
    environment:
      - WOODPECKER_OPEN=true
      - WOODPECKER_HOST=http://${PUBLIC_IP}:8000
      - WOODPECKER_GITHUB=true
      - WOODPECKER_GITHUB_CLIENT=${GH_CLIENT_ID}
      - WOODPECKER_GITHUB_SECRET=${GH_SECRET}
      - WOODPECKER_AGENT_SECRET=secret-token

  woodpecker-agent:
    image: woodpeckerci/woodpecker-agent:latest
    command: agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WOODPECKER_SERVER=woodpecker-server:9000
      - WOODPECKER_AGENT_SECRET=secret-token
EOC

# 3. .woodpecker.yml の作成 (GitHubリポジトリに置く用のサンプル)
cat << EOW > .woodpecker.yml
pipeline:
  test:
    image: ovhcom/venom:latest
    commands:
      - venom run tests/*.venom.yml --var "db_url=postgres://postgres:password123@${DB_ENDPOINT}:5432/testdb" --var "api_url=${API_URL}"
EOW

# 4. Venomテスト定義の作成
cat << EOV > tests/api_db_test.venom.yml
name: API Integration Test with Aurora
vars:
  api_url: "${API_URL}"
  db_url: "postgres://postgres:password123@${DB_ENDPOINT}:5432/testdb"

testcases:
  - name: Check API response after DB update
    steps:
      - type: dbfixtures
        database: postgres
        dsn: "{{.db_url}}"
        commands:
          - "CREATE TABLE IF NOT EXISTS users (id INT, name TEXT, status TEXT);"
          - "INSERT INTO users (id, name, status) VALUES (100, 'Test User', 'inactive') ON CONFLICT DO NOTHING;"
          - "UPDATE users SET status = 'active' WHERE id = 100;"

      - type: http
        method: GET
        url: "{{.api_url}}/users/100"
        assertions:
          - result.statuscode ShouldEqual 200
          - result.bodyjson.status ShouldEqual "active"
EOV

# 5. Woodpeckerの起動
echo "Starting Woodpecker..."
docker-compose up -d

echo "=== Setup Complete ==="
echo "Access Woodpecker UI at http://${PUBLIC_IP}:8000"
echo "NOTE: Please commit '.woodpecker.yml' and 'tests/' directory to your GitHub repository."
