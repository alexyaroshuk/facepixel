#!/bin/bash
set -e

echo "Installing Flutter..."
cd /tmp
git clone https://github.com/flutter/flutter.git --depth 1 -b stable
export PATH="/tmp/flutter/bin:$PATH"

echo "Verifying Flutter installation..."
flutter --version

echo "Current directory: $(pwd)"
echo "Getting dependencies..."
flutter pub get

echo "Building for web..."
flutter build web --release

echo "Build complete!"
