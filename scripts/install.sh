#!/bin/bash
# Install Chrome Control native messaging host

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_NAME="com.chrome_control.host"

# Create native host manifest
MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
mkdir -p "$MANIFEST_DIR"

cat > "$MANIFEST_DIR/$HOST_NAME.json" << EOF
{
  "name": "$HOST_NAME",
  "description": "Chrome Control Native Messaging Host",
  "path": "$SCRIPT_DIR/native_host",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://*"
  ]
}
EOF

# NOTE: The allowed_origins wildcard "chrome-extension://*" is intentional for
# unpacked extensions, where the extension ID changes on each install. For
# production, replace with your specific extension ID in the manifest:
#   "chrome-extension://YOUR_EXTENSION_ID/"

# Create launcher script (resolves path relative to itself at runtime)
cat > "$SCRIPT_DIR/native_host" << 'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec /usr/bin/env python3 "$DIR/native_host.py"
EOF

chmod +x "$SCRIPT_DIR/native_host"
chmod +x "$SCRIPT_DIR/native_host.py"

echo "Native messaging host installed!"
echo "Manifest: $MANIFEST_DIR/$HOST_NAME.json"
echo "Host: $SCRIPT_DIR/native_host"
echo ""
echo "Next steps:"
echo "1. Go to chrome://extensions/"
echo "2. Enable Developer Mode"
echo "3. Click 'Load unpacked' and select: extension/"
