#!/bin/bash
set -e

# Store the project directory before we cd
PROJECT_DIR="$(pwd)"

echo "Installing Flutter..."
cd /tmp
git clone https://github.com/flutter/flutter.git --depth 1 -b stable
export PATH="/tmp/flutter/bin:$PATH"

echo "Verifying Flutter installation..."
flutter --version

echo "Returning to project directory: $PROJECT_DIR"
cd "$PROJECT_DIR"

echo "Getting dependencies..."
flutter pub get

echo "Building for web..."
flutter build web --release

echo "Build complete!"
