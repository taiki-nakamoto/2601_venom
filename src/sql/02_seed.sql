-- DML: 初期データ投入
INSERT INTO users (id, username, email, address, status, created_by, updated_by)
VALUES (100, 'test_user_01', 'test@example.com', 'Tokyo, Japan', 'inactive', 'setup_script', 'setup_script')
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status;
