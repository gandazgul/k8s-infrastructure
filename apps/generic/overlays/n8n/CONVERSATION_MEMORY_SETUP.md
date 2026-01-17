# N8N Conversation Memory Setup Guide

This guide will help you set up persistent conversation memory for your Home Assistant Calendar Agent using the shared PostgreSQL database.

## Overview

The solution stores conversation history in PostgreSQL, allowing the AI agent to remember previous messages within a conversation. This solves the context loss issue when the LLM asks for confirmation.

## Prerequisites

- Self-hosted n8n in Kubernetes
- Paperless PostgreSQL cluster (`paperless-db`) running
- Access to n8n UI
- kubectl access to your cluster

---

## Step 1: Generate Database Password

First, generate a secure password for the n8n database user:

```bash
# Generate a random password
openssl rand -base64 32
```

Save this password - you'll need it in the next steps.

---

## Step 2: Update Database Initialization Script

Edit the password in the ConfigMap:

```bash
cd /Users/rgil/projects/personal/k8s-infrastructure/apps/generic/overlays/n8n
```

Open `db-init-job.yaml` and replace `CHANGE_THIS_PASSWORD` with your generated password on line 16.

---

## Step 3: Run Database Initialization

Apply the Kubernetes Job to create the database and tables:

```bash
kubectl apply -f /Users/rgil/projects/personal/k8s-infrastructure/apps/generic/overlays/n8n/db-init-job.yaml
```

Check the job status:

```bash
kubectl get jobs -n default | grep n8n-db-init
kubectl logs job/n8n-db-init -n default
```

You should see output like:
```
Waiting for PostgreSQL to be ready...
PostgreSQL is ready. Running initialization script...
CREATE DATABASE
\c n8n_conversations
CREATE USER
CREATE TABLE
CREATE INDEX
GRANT
GRANT
CREATE FUNCTION
GRANT
Database initialization complete!
```

---

## Step 4: Get PostgreSQL Connection Details

Get the host and port from the paperless-db service:

```bash
# Get the host
kubectl get svc -n default | grep paperless-db

# The host will be: paperless-db-rw.default.svc.cluster.local
# Port: 5432
```

---

## Step 5: Add PostgreSQL Credential to n8n

1. Open n8n UI: `https://n8n.dumbhome.uk`
2. Click your profile icon (top right) → **Credentials**
3. Click **Add Credential**
4. Search for "Postgres" and select **Postgres**
5. Fill in the details:
   - **Name**: `N8N Conversations DB`
   - **Host**: `paperless-db-rw.default.svc.cluster.local`
   - **Port**: `5432`
   - **Database**: `n8n_conversations`
   - **User**: `n8n_app`
   - **Password**: `[Your generated password from Step 1]`
   - **SSL Mode**: `disable` (since it's internal cluster traffic)
6. Click **Test Connection** to verify
7. Click **Save**

**Important:** Note the credential ID for the next step. You can find it in the URL when editing the credential: 
`https://n8n.dumbhome.uk/credentials/[CREDENTIAL_ID]`

---

## Step 6: Import Updated Workflow

### Option A: Import New Workflow (Recommended)

1. In n8n UI, click **Workflows** → **Add workflow** → **Import from File**
2. Select the file: `/Users/rgil/projects/personal/k8s-infrastructure/apps/generic/overlays/n8n/workflow-ha-calendar-with-memory.json`
3. After import, the workflow will open
4. For each node with credentials:
   - **Get Conversation Memory** node: Select your "N8N Conversations DB" credential
   - **Save Conversation Memory** node: Select your "N8N Conversations DB" credential  
   - **OpenAI Chat Model** node: Select your existing OpenAI credential
   - **Google Calendar nodes** (3 nodes): Select your existing Google Calendar credential
5. Click **Save** (top right)
6. Click **Active** toggle to enable the workflow
7. **Deactivate your old workflow** to avoid conflicts

### Option B: Manual Update (Advanced)

If you prefer to update your existing workflow manually:
1. Open your existing "Home Assistant Calendar Agent" workflow
2. Add the new nodes as shown in the workflow JSON
3. Update connections between nodes
4. Add PostgreSQL credential references

---

## Step 7: Test the Setup

### Test 1: Verify Database Connection

1. In n8n, create a test workflow with a manual trigger
2. Add a Postgres node
3. Select your "N8N Conversations DB" credential
4. Operation: "Execute Query"
5. Query: `SELECT * FROM conversations;`
6. Click "Execute Node"
7. Should return empty results (or existing conversations if you've tested already)

### Test 2: Test from Home Assistant

1. Open Home Assistant
2. Go to Settings → Voice Assistants → Find your "n8n" assistant
3. Click the three dots → Start conversation
4. Test multi-turn conversation:
   ```
   You: "Create a calendar event tomorrow at 3pm"
   AI: "What is the title for the event?"
   You: "Doctor appointment"
   AI: [Should remember you want to create an event and ask for more details]
   ```

The AI should now remember the context of the conversation!

---

## Step 8: Verify Conversation Storage

Check that conversations are being stored:

```bash
kubectl exec -it deployment/n8n -n default -- sh
apk add postgresql-client
psql -h paperless-db-rw.default.svc.cluster.local -U n8n_app -d n8n_conversations
# Password: [your generated password]

# List all conversations
SELECT conversation_id, updated_at, length(history) as history_size FROM conversations;

# View a specific conversation
SELECT * FROM conversations WHERE conversation_id = 'default';
```

---

## Cleanup (Optional)

To clean up old conversations (older than 30 days):

```bash
psql -h paperless-db-rw.default.svc.cluster.local -U n8n_app -d n8n_conversations
SELECT cleanup_old_conversations();
```

Or set up a cron job to do this automatically.

---

## Troubleshooting

### Issue: "relation \"conversations\" does not exist"

The database initialization didn't run properly. Check:
```bash
kubectl logs job/n8n-db-init -n default
```

Re-run if needed:
```bash
kubectl delete job n8n-db-init -n default
kubectl apply -f db-init-job.yaml
```

### Issue: "password authentication failed for user \"n8n_app\""

Password mismatch. Verify:
1. Password in db-init-job.yaml ConfigMap
2. Password in n8n PostgreSQL credential

### Issue: Workflow not receiving conversation_id

Home Assistant's webhook-conversation integration automatically sends `conversation_id` in the payload. Verify:
1. You're using the webhook-conversation integration (not standard conversation)
2. The integration is configured with your webhook URL

### Issue: Conversations not persisting

Check PostgreSQL node is not failing:
1. Open workflow execution history
2. Look for any red (failed) nodes
3. Check "Save Conversation Memory" node output

---

## Architecture

```
Home Assistant → Webhook → Extract Message & Conv ID → Get Memory from DB
                                                              ↓
                                                        Check if exists?
                                                         /          \
                                                      Yes            No
                                                       ↓              ↓
                                              Load History    Initialize New
                                                       \            /
                                                        ↓          ↓
                                                    AI Agent Process
                                                          ↓
                                              Format Response & Update History
                                                          ↓
                                                   Save to Database
                                                          ↓
                                                   Respond to HA
```

## Conversation Data Structure

Each conversation is stored as:
```json
{
  "conversation_id": "abc123",
  "history": "[{\"role\":\"user\",\"content\":\"Create event\"},{\"role\":\"assistant\",\"content\":\"What time?\"}]",
  "created_at": "2025-12-30T23:00:00Z",
  "updated_at": "2025-12-30T23:05:00Z"
}
```

The workflow keeps the last 20 messages (10 exchanges) per conversation to prevent the history from growing too large.

---

## Success!

You now have persistent conversation memory for your Home Assistant voice assistant! 🎉

When the AI asks for confirmation or follow-up questions, it will remember the previous context and act accordingly.
