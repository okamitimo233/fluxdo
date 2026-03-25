#!/bin/bash
# Build Rust DOH Proxy for iOS (device + simulator)
# Usage: ./scripts/build_ios.sh [--debug]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/core/doh_proxy"
IOS_LIBS_DIR="$PROJECT_ROOT/ios/rust_libs"

# Default to release build
BUILD_TYPE="release"
CARGO_FLAG="--release"

if [ "$1" == "--debug" ]; then
    BUILD_TYPE="debug"
    CARGO_FLAG=""
fi

echo "=== Building Rust DOH Proxy for iOS ($BUILD_TYPE) ==="

# Check if iOS targets are installed
echo "Checking Rust iOS targets..."
for target in aarch64-apple-ios aarch64-apple-ios-sim; do
    if ! rustup target list --installed | grep -q "$target"; then
        echo "Adding target: $target"
        rustup target add "$target"
    fi
done

# 自动生成证书（如果不存在）
if [ ! -f "$RUST_DIR/certs/ca.crt" ]; then
    echo "Generating CA certificates..."
    (cd "$RUST_DIR" && cargo run --bin gen_ca)
fi

# iOS 不支持 cdylib，只编译 staticlib（通过 cargo rustc 覆盖 crate-type）
cd "$RUST_DIR"

# Build for device (arm64)
echo "Building for iOS device (aarch64-apple-ios)..."
cargo rustc $CARGO_FLAG --target aarch64-apple-ios --features ech --lib --crate-type staticlib

# Build for simulator (arm64)
echo "Building for iOS simulator (aarch64-apple-ios-sim)..."
cargo rustc $CARGO_FLAG --target aarch64-apple-ios-sim --features ech --lib --crate-type staticlib

# Create output directories
echo "Creating output directories..."
mkdir -p "$IOS_LIBS_DIR/device"
mkdir -p "$IOS_LIBS_DIR/simulator"

# Copy libraries
echo "Copying libraries..."
cp "$RUST_DIR/target/aarch64-apple-ios/$BUILD_TYPE/libdoh_proxy.a" "$IOS_LIBS_DIR/device/"
cp "$RUST_DIR/target/aarch64-apple-ios-sim/$BUILD_TYPE/libdoh_proxy.a" "$IOS_LIBS_DIR/simulator/"

echo ""
echo "=== Build complete! ==="
echo "Device library:"
ls -lh "$IOS_LIBS_DIR/device/libdoh_proxy.a"
echo "Simulator library:"
ls -lh "$IOS_LIBS_DIR/simulator/libdoh_proxy.a"
