#!/bin/bash
set -e

# Build EFI Bootloader Script
# Usage: ./script/build_efi.sh

# Configuration
EFI_FILENAME_PREFIX=${EFI_FILENAME_PREFIX:-"netboot.xyz-rampart-aios"}
DOCKER_PLATFORM=${DOCKER_PLATFORM:-"linux/amd64"}
COMMIT_HASH=${COMMIT_HASH:-$(git rev-parse --short HEAD)}
BRANCH_NAME=${BRANCH_NAME:-$(git rev-parse --abbrev-ref HEAD)}
# Sanitize branch name for filename (replace / with - and remove special chars)
SAFE_BRANCH_NAME=$(echo $BRANCH_NAME | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/\/-/-/g')
SHORT_HASH=$(echo $COMMIT_HASH | cut -c1-7)

echo "=== Building EFI Bootloader ==="
echo "Platform: $DOCKER_PLATFORM"
echo "Commit Hash: $COMMIT_HASH"
echo "Short Hash: $SHORT_HASH"
echo "Branch Name: $BRANCH_NAME"
echo "Safe Branch Name: $SAFE_BRANCH_NAME"

# Build EFI bootloader
echo "Building EFI bootloader..."
docker build -t localbuild --platform=$DOCKER_PLATFORM -f Dockerfile .
docker run --rm -i --platform=$DOCKER_PLATFORM -v $(pwd):/buildout localbuild

# Verify build output
echo "Verifying build output..."
if [ ! -f "buildout/ipxe/netboot.xyz.efi" ]; then
    echo "ERROR: EFI file not found after build"
    exit 1
fi
echo "EFI build completed successfully"

# Display build information
echo "=== Build Information ==="
echo "Generated EFI files:"
ls -la buildout/ipxe/

echo "=== EFI File Details ==="
file buildout/ipxe/netboot.xyz.efi

echo "=== EFI Size ==="
du -h buildout/ipxe/netboot.xyz.efi

# Verify EFI content
echo "=== EFI Content Verification ==="
strings ./buildout/ipxe/netboot.xyz.efi | grep -i "rampart-aios" || echo "INFO: Custom content not found (this is normal for standard builds)"

# Rename EFI file
echo "Renaming EFI file..."
cp buildout/ipxe/netboot.xyz.efi buildout/ipxe/$EFI_FILENAME_PREFIX-$SAFE_BRANCH_NAME-$SHORT_HASH.efi

# Verify renamed file
if [ ! -f "buildout/ipxe/$EFI_FILENAME_PREFIX-$SAFE_BRANCH_NAME-$SHORT_HASH.efi" ]; then
    echo "ERROR: Renamed EFI file not found"
    exit 1
fi

echo "Renamed EFI file to $EFI_FILENAME_PREFIX-$SAFE_BRANCH_NAME-$SHORT_HASH.efi"
echo "Renamed file verified:"
ls -la buildout/ipxe/$EFI_FILENAME_PREFIX-$SAFE_BRANCH_NAME-$SHORT_HASH.efi

echo "=== Build completed successfully ===" 