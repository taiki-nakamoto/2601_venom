-- DDL: テーブル作成
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
