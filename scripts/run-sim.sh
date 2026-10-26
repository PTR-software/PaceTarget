#!/bin/bash
# Rebuilds pace-target and (re)launches it in the Connect IQ simulator.
# Usage: scripts/run-sim.sh [device]   (default device: venu3)
set -e

DEVICE="${1:-venu3}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DIR=$(find "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" -maxdepth 1 -iname "connectiq-sdk-mac-*" | sort | tail -1)
SDKBIN="$SDK_DIR/bin"
KEY="$HOME/Library/Application Support/Garmin/ConnectIQ/developer_key.der"
export JAVA_HOME="$(brew --prefix openjdk)/libexec/openjdk.jdk/Contents/Home"

echo "SDK: $SDK_DIR"
echo "Device: $DEVICE"

echo "==> Killing any existing simulator..."
pkill -9 -f "ConnectIQ.app/Contents/MacOS/simulator" 2>/dev/null || true
sleep 2

echo "==> Building..."
cd "$PROJECT_DIR"
"$SDKBIN/monkeyc" -f monkey.jungle -o "bin/pace-target-$DEVICE.prg" -d "$DEVICE" -y "$KEY"

echo "==> Launching simulator..."
nohup "$SDKBIN/connectiq" > /tmp/ciq_sim.log 2>&1 &
disown

echo "==> Waiting for simulator to come up..."
for i in $(seq 1 30); do
    sleep 1
    if lsof -i -P 2>/dev/null | grep -q "TCP \*:1234 (LISTEN)"; then
        echo "    listening after ${i}s"
        break
    fi
done

echo "==> Giving it time to fully settle (device assets, etc)..."
sleep 20

echo "==> Pushing app..."
"$SDKBIN/monkeydo" "bin/pace-target-$DEVICE.prg" "$DEVICE"

echo "==> Done. If the sim window isn't focused, check the Dock / Mission Control."
