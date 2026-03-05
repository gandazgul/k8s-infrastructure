-- Create database for n8n conversations
CREATE DATABASE n8n_conversations;

-- Connect to the new database
\c n8n_conversations;

-- Create user for n8n
CREATE USER n8n_app WITH PASSWORD 'CHANGE_THIS_PASSWORD';

-- Create conversations table
CREATE TABLE IF NOT EXISTS conversations (
    conversation_id VARCHAR(255) PRIMARY KEY,
    history TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index on updated_at for efficient cleanup queries
CREATE INDEX idx_conversations_updated_at ON conversations(updated_at);

-- Grant permissions to n8n user
GRANT CONNECT ON DATABASE n8n_conversations TO n8n_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE conversations TO n8n_app;

-- Optional: Create a cleanup function to remove old conversations (older than 30 days)
CREATE OR REPLACE FUNCTION cleanup_old_conversations()
RETURNS void AS $$
BEGIN
    DELETE FROM conversations 
    WHERE updated_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- Grant execute on cleanup function
GRANT EXECUTE ON FUNCTION cleanup_old_conversations() TO n8n_app;
