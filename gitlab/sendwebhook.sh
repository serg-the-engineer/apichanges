#!/bin/bash

# Check if the webhook URL is provided
if [ -z "$WEBHOOK_URL" ]; then
    echo "Error: Webhook URL is not specified. Set the WEBHOOK_URL variable."
    exit 1
fi

if [ -z "$PAGES_URL" ]; then
    echo "Error: GitLab Pages URL is not specified. Set the PAGES_URL variable."
    exit 1
fi

# Check if the header is provided
if [ -z "$HEADER" ]; then
    echo "Error: Message header is not specified. Set the HEADER variable."
    exit 1
fi

# Check if the required files exist
if [ ! -f "summary.yaml" ] || [ ! -f "breaking.md" ]; then
    echo "Error: Files summary.yaml and/or breaking.md not found."
    exit 1
fi

# Create a temporary file for the message
TEMP_FILE=$(mktemp)

# If the first line of the file contains "diff: false", assume there are no changes
HAS_CHANGES=true
if [ -f "summary.yaml" ]; then
    # Get the first line of the file and remove spaces
    FIRST_LINE=$(head -n 1 summary.yaml | tr -d ' ')

    # Check if the first line contains "diff:false"
    if [ "$FIRST_LINE" = "diff:false" ]; then
        HAS_CHANGES=false
    fi
fi

if [ "$HAS_CHANGES" = "true" ]; then
    # If there are API changes
    SUMMARY_CONTENT=$(tail +2 summary.yaml)

    # Get the breaking changes content
    if [ -f "breaking.md" ] && [ -s "breaking.md" ] && [ "$(grep -v '^\s*$' breaking.md)" ]; then
        # If there are breaking changes, include them in the message
        BREAKING_CONTENT=$(head -n 50 breaking.md)
        MESSAGE_TEXT="$HEADER\n\`\`\`$SUMMARY_CONTENT\n\n💔 BREAKING CHANGES\n\n$BREAKING_CONTENT\`\`\`\n$PAGES_URL\n\n\n"
    else
        # If there are no breaking changes, exclude this block
        MESSAGE_TEXT="$HEADER\n\`\`\`$SUMMARY_CONTENT\n\`\`\`\n$PAGES_URL"
    fi
else
    # If there are no API changes
    MESSAGE_TEXT="$HEADER: No changes"
fi

# Create the JSON payload for the webhook
cat > $TEMP_FILE << EOF
{
  "text": "$MESSAGE_TEXT"
}
EOF

# Send the message via webhook
echo "Sending data via webhook..."
curl -X POST --data-urlencode "payload=$(cat $TEMP_FILE)" "$WEBHOOK_URL"

# Check the result of the webhook request
if [ $? -eq 0 ]; then
    echo "Summary data successfully sent via webhook."
else
    echo "Error sending summary data via webhook."
fi

# Remove the temporary file
rm -f $TEMP_FILE