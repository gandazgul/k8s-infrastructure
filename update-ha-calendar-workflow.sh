#!/bin/bash

# This script updates the Home Assistant Calendar Agent workflow to use
# Home Assistant's conversation history management

WORKFLOW_ID="Vt7ccx17KJ0zyUgY"
N8N_URL="https://n8n.dumbhome.uk"

# Backup the existing workflow first
echo "Backing up existing workflow..."
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}" > /tmp/ha-calendar-workflow-backup.json

echo "Backup saved to /tmp/ha-calendar-workflow-backup.json"

# The workflow will be updated to:
# 1. Remove "Extract Message" node
# 2. Add "Prepare Messages" Code node that formats Home Assistant's messages
# 3. Keep the AI Agent but configure it to use the formatted messages
# 4. Everything else stays the same

# Since we can't easily update the workflow via API with the complex changes needed,
# we'll need to do this through the UI

echo ""
echo "==================================================================="
echo "Manual steps required (the workflow is too complex to update via API):"
echo "==================================================================="
echo ""
echo "1. Open the workflow in n8n: ${N8N_URL}/workflow/${WORKFLOW_ID}"
echo ""
echo "2. Delete the 'Extract Message' node"
echo ""
echo "3. Add a new 'Code' node between 'Webhook' and 'Calendar AI Agent'"
echo "   Name it: 'Prepare Messages for OpenAI'"
echo ""
echo "4. In the Code node, paste this code:"
echo ""
cat << 'EOF'
// Extract the data from Home Assistant
const body = $input.item.json.body;
const messages = body.messages || [];
const systemPrompt = body.system_prompt || "You are a helpful assistant.";
const query = body.query;

// Format messages for the AI Agent
// Home Assistant sends messages in {role, content} format which is perfect for OpenAI
const formattedMessages = [
  { role: 'system', content: systemPrompt },
  ...messages,
  { role: 'user', content: query }
];

return {
  json: {
    messages: formattedMessages,
    conversation_id: body.conversation_id
  }
};
EOF
echo ""
echo "5. Update the 'Calendar AI Agent' node:"
echo "   - Click on the node"
echo "   - Go to 'Memory' section"
echo "   - Remove/disable the Window Buffer Memory"
echo "   - The agent will now use the messages we provide"
echo ""
echo "6. Update the connection from 'Prepare Messages for OpenAI' to 'Calendar AI Agent'"
echo ""
echo "7. Test the workflow by saying something in Home Assistant"
echo ""
echo "==================================================================="
