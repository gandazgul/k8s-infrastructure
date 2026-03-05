# N8N Conversation Memory - Quick Setup

The database has been set up in the paperless PostgreSQL cluster. Now you just need to:

## 1. Run the Database Initialization

The database schema has been created. Run the init job:

```bash
kubectl apply -f /Users/rgil/projects/personal/k8s-infrastructure/apps/generic/overlays/n8n/db-init-job.yaml
```

Wait for completion:
```bash
kubectl wait --for=condition=complete --timeout=60s job/n8n-db-init -n default
kubectl logs job/n8n-db-init -n default
```

You should see:
```
PostgreSQL is ready. Running initialization script...
CREATE SCHEMA
CREATE TABLE
CREATE INDEX
CREATE FUNCTION
Database initialization complete!
```

## 2. Add PostgreSQL Credential to n8n

1. Go to https://n8n.dumbhome.uk
2. Click your profile → **Credentials** → **Add Credential**
3. Select **Postgres**
4. Fill in:
   - **Name**: `N8N Conversations DB`
   - **Host**: `paperless-db-rw.default.svc.cluster.local`
   - **Port**: `5432`
   - **Database**: `paperless`  ← Using paperless database
   - **Schema**: `n8n`  ← Our conversation schema
   - **User**: Get from: `kubectl get secret paperless-db-app -n default -o jsonpath='{.data.username}' | base64 -d`
   - **Password**: Get from: `kubectl get secret paperless-db-app -n default -o jsonpath='{.data.password}' | base64 -d`
   - **SSL Mode**: `disable`
5. Click **Test Connection**
6. Click **Save**

## 3. Import the Updated Workflow

1. In n8n, go to **Workflows** → **Import from File**
2. Select: `/Users/rgil/projects/personal/k8s-infrastructure/apps/generic/overlays/n8n/workflow-ha-calendar-with-memory.json`
3. After import, update credentials in these nodes:
   - **Get Conversation Memory**: Select "N8N Conversations DB"
   - **Save Conversation Memory**: Select "N8N Conversations DB"
   - **OpenAI Chat Model**: Select your existing OpenAI credential
   - **All Google Calendar nodes** (3 total): Select your existing Google Calendar credential
4. Update the PostgreSQL queries to use the `n8n` schema:
   - In "Get Conversation Memory" node, change query to:
     ```sql
     SELECT history FROM n8n.conversations WHERE conversation_id = $1
     ```
   - In "Save Conversation Memory" node, change query to:
     ```sql
     INSERT INTO n8n.conversations (conversation_id, history, updated_at) 
     VALUES ($1, $2, $3) 
     ON CONFLICT (conversation_id) 
     DO UPDATE SET history = EXCLUDED.history, updated_at = EXCLUDED.updated_at
     ```
5. Click **Save**
6. Toggle **Active** to enable
7. **Deactivate your old workflow** to avoid conflicts

## 4. Test It!

1. Go to Home Assistant → Settings → Voice Assistants
2. Find your n8n assistant → Start conversation
3. Try a multi-turn conversation:
   ```
   You: "Create an event tomorrow at 3pm"
   AI: "What should I title the event?"
   You: "Doctor appointment"
   AI: [Should remember you're creating an event and proceed]
   ```

## Troubleshooting

### Check if database is initialized:
```bash
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=cnpg -n default -o name | head -1) -n default -- psql -U paperless -d paperless -c "\dn"
```

You should see the `n8n` schema listed.

### Check if table exists:
```bash
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=cnpg -n default -o name | head -1) -n default -- psql -U paperless -d paperless -c "\dt n8n.*"
```

You should see `n8n.conversations` table.

### View stored conversations:
```bash
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=cnpg -n default -o name | head -1) -n default -- psql -U paperless -d paperless -c "SELECT conversation_id, updated_at, length(history) as history_size FROM n8n.conversations;"
```

## Success!

Your Home Assistant voice assistant now has persistent conversation memory! 🎉
