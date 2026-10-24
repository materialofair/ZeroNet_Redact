#!/bin/sh
# Run the production geometry and XCTest cases without a simulator or MuPDF.
set -eu
REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/cloakmark-editor-geometry.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/Sources/EditorGeometry" "$TEST_DIR/Tests/EditorGeometryTests"
cp "$REPO_ROOT/zeroNetRedact/zeroNetRedact/Views/BrushEditor/EditorCanvasGeometry.swift" "$TEST_DIR/Sources/EditorGeometry/"
cp "$REPO_ROOT/zeroNetRedact/zeroNetRedactTests/EditorCanvasGeometryTests.swift" "$TEST_DIR/Tests/EditorGeometryTests/"
cat > "$TEST_DIR/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "EditorGeometry", targets: [
    .target(name: "EditorGeometry"),
    .testTarget(name: "EditorGeometryTests", dependencies: ["EditorGeometry"])
])
SWIFT
swift test --package-path "$TEST_DIR" --scratch-path "$TEST_DIR/.build"
