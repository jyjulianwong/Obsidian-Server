#!/usr/bin/env bash
# Wraps a provisioned device's .p12 into an iOS/macOS configuration profile
# (.mobileconfig) with a proper display name + description.
#
# AirDropping/emailing the raw .p12 directly makes iOS install it as a bare
# "Identity Certificate" in Settings -> VPN & Device Management, with no name
# or description — easy to confuse with other profiles on the device. A
# .mobileconfig wrapper lets us set PayloadDisplayName/PayloadDescription so
# it shows up clearly labeled instead.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <device_id>" >&2
  exit 1
fi

DEVICE_ID="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_DIR="$ROOT_DIR/devices/$DEVICE_ID"
P12_PATH="$DEVICE_DIR/$DEVICE_ID.p12"
MOBILECONFIG_PATH="$DEVICE_DIR/$DEVICE_ID.mobileconfig"

if [[ ! -f "$P12_PATH" ]]; then
  echo "Missing $P12_PATH — run scripts/generate_mtls_bundle.sh $DEVICE_ID first." >&2
  exit 1
fi

if ! command -v uuidgen >/dev/null; then
  echo "uuidgen not found — required to generate PayloadUUIDs." >&2
  exit 1
fi

P12_BASE64="$(base64 < "$P12_PATH")"
PROFILE_UUID="$(uuidgen)"
PAYLOAD_UUID="$(uuidgen)"

cat > "$MOBILECONFIG_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>PayloadContent</key>
	<array>
		<dict>
			<key>PayloadCertificateFileName</key>
			<string>$DEVICE_ID.p12</string>
			<key>PayloadContent</key>
			<data>
$P12_BASE64
			</data>
			<key>PayloadDescription</key>
			<string>Obsidian mTLS client identity for device "$DEVICE_ID". Used only to authenticate to auth.jyjwong.com.</string>
			<key>PayloadDisplayName</key>
			<string>Obsidian Device Identity: $DEVICE_ID</string>
			<key>PayloadIdentifier</key>
			<string>com.jyjulianwong.obsidian.device.$DEVICE_ID.identity</string>
			<key>PayloadType</key>
			<string>com.apple.security.pkcs12</string>
			<key>PayloadUUID</key>
			<string>$PAYLOAD_UUID</string>
			<key>PayloadVersion</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>PayloadDescription</key>
	<string>Installs the Obsidian mTLS client certificate that authenticates this device to auth.jyjwong.com. Safe to remove if you decommission this device.</string>
	<key>PayloadDisplayName</key>
	<string>Obsidian: $DEVICE_ID</string>
	<key>PayloadIdentifier</key>
	<string>com.jyjulianwong.obsidian.device.$DEVICE_ID</string>
	<key>PayloadOrganization</key>
	<string>Obsidian</string>
	<key>PayloadRemovalDisallowed</key>
	<false/>
	<key>PayloadType</key>
	<string>Configuration</string>
	<key>PayloadUUID</key>
	<string>$PROFILE_UUID</string>
	<key>PayloadVersion</key>
	<integer>1</integer>
</dict>
</plist>
PLIST

echo "Created $MOBILECONFIG_PATH"
echo "AirDrop or email this file instead of the raw .p12 — it will still prompt"
echo "for the export password, but Settings will show \"Obsidian: $DEVICE_ID\""
echo "instead of a bare \"Identity Certificate\"."
