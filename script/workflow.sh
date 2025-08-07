#!/bin/bash

# Unified Workflow Script
# Contains all functions for building, testing, and releasing EFI bootloaders
# Usage: source ./script/workflow.sh

set -e

# Configuration
EFI_FILENAME_PREFIX="netboot.xyz-rampart-aios"
ARTIFACT_RETENTION_DAYS=90
DEFAULT_VERSION_TYPE="minor"
MINOR_VERSION_PREFIX="v0"
MAJOR_VERSION_PREFIX="v"
DEFAULT_RELEASE_NOTES="Release of Rampart-AIOS iPXE EFI bootloader"
DRAFT_RELEASE_NOTES="Draft Release of Rampart-AIOS iPXE EFI bootloader"
PYTHON_VERSION="3.13"
ANSIBLE_VERSION="10.2.0"
ANSIBLE_LINT_VERSION="24.7.0"

# Logging functions
log_info() {
    echo "INFO: $1"
}

log_success() {
    echo "SUCCESS: $1"
}

log_warning() {
    echo "WARNING: $1"
}

log_error() {
    echo "ERROR: $1"
}

log_debug() {
    echo "DEBUG: $1"
}

# Version management functions
get_commit_hash() {
    local short_hash=$(git rev-parse --short HEAD)
    echo "short_hash=$short_hash"
    log_info "Commit hash: $short_hash"
}

get_version() {
    local version_type=${1:-"$DEFAULT_VERSION_TYPE"}
    
    log_info "Getting $version_type version..."
    
    if [ "$version_type" = "minor" ]; then
        # Get the latest minor version from existing releases
        local latest_minor=$(gh release list --limit 1000 | grep "$MINOR_VERSION_PREFIX\." | head -1 | awk '{print $1}' | sed 's/v//')
        
        if [ -z "$latest_minor" ]; then
            # No existing minor versions, start with v0.0.1
            local new_version="0.0.1"
        else
            # Extract patch number and increment
            local patch=$(echo $latest_minor | awk -F'.' '{print $3}')
            local new_patch=$((patch + 1))
            local new_version="0.0.$new_patch"
        fi
        
        echo "version=v$new_version"
        log_success "Generated minor version: v$new_version"
        
    elif [ "$version_type" = "major" ]; then
        # Get the latest major version from existing releases
        local latest_major=$(gh release list --limit 1000 | grep "v[1-9]" | head -1 | awk '{print $1}' | sed 's/v//')
        
        if [ -z "$latest_major" ]; then
            # No existing major versions, start with v1.0.0
            local new_version="1.0.0"
        else
            # Extract major number and increment
            local major=$(echo $latest_major | awk -F'.' '{print $1}')
            local new_major=$((major + 1))
            local new_version="$new_major.0.0"
        fi
        
        echo "version=v$new_version"
        log_success "Generated major version: v$new_version"
        
    else
        log_error "Invalid version type. Use 'minor' or 'major'"
        exit 1
    fi
}

# Build functions
build_efi() {
    local version=${1:-"commit-hash"}
    
    log_info "Building EFI bootloader..."
    log_debug "Version: $version"
    
    # Build EFI bootloader
    log_info "Building EFI bootloader..."
    docker build -t localbuild -f Dockerfile .
    docker run --rm -i -v $(pwd):/buildout localbuild
    
    # Verify EFI content
    log_info "Verifying EFI content..."
    log_debug "Generated EFI files:"
    ls -la buildout/ipxe/netboot.xyz.efi
    
    log_debug "Verifying custom chain command in EFI file:"
    strings ./buildout/ipxe/netboot.xyz.efi | grep -i "rampart-aios" || log_warning "Custom content not found (this is normal for standard builds)"
    
    # Rename EFI file
    log_info "Renaming EFI file..."
    cp buildout/ipxe/netboot.xyz.efi buildout/ipxe/$EFI_FILENAME_PREFIX-$version.efi
    log_success "Renamed netboot.xyz.efi to $EFI_FILENAME_PREFIX-$version.efi"
    
    log_success "EFI build completed successfully!"
    log_info "Output: buildout/ipxe/$EFI_FILENAME_PREFIX-$version.efi"
}

# Release functions
create_release() {
    local version=$1
    local title=${2:-"$version"}
    local notes=${3:-"$DEFAULT_RELEASE_NOTES"}
    local draft=${4:-"false"}
    local prerelease=${5:-"false"}
    
    if [ -z "$version" ]; then
        log_error "Version is required"
        log_info "Usage: create_release [version] [title] [notes] [draft] [prerelease]"
        exit 1
    fi
    
    log_info "Creating GitHub release..."
    log_debug "Version: $version"
    log_debug "Title: $title"
    log_debug "Draft: $draft"
    log_debug "Prerelease: $prerelease"
    
    # Create release
    log_info "Creating release..."
    gh release create $version \
        --title "$title" \
        --notes "$notes" \
        --draft=$draft \
        --prerelease=$prerelease
    
    # Upload EFI to release
    log_info "Uploading EFI to release..."
    gh release upload $version \
        buildout/ipxe/$EFI_FILENAME_PREFIX-$version.efi \
        --clobber
    
    log_success "Release created successfully!"
    log_info "Release URL: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$version"
}

# Test functions
test_ansible() {
    local python_version=${1:-"$PYTHON_VERSION"}
    local ansible_version=${2:-"$ANSIBLE_VERSION"}
    local ansible_lint_version=${3:-"$ANSIBLE_LINT_VERSION"}
    
    log_info "Running Ansible tests..."
    log_debug "Python version: $python_version"
    log_debug "Ansible version: $ansible_version"
    log_debug "Ansible-lint version: $ansible_lint_version"
    
    # Install dependencies
    log_info "Installing dependencies..."
    python -m pip install --upgrade pip
    pip install ansible==$ansible_version
    pip install ansible-lint==$ansible_lint_version
    
    # Syntax check
    log_info "Running syntax check..."
    ansible-playbook site.yml --syntax-check
    
    # Ansible lint
    log_info "Running Ansible lint..."
    ansible-lint -v roles/netbootxyz/tasks
    
    log_success "Ansible tests completed successfully!"
}

# Utility functions
upload_artifact() {
    local version=$1
    local retention_days=${2:-"$ARTIFACT_RETENTION_DAYS"}
    
    log_info "Uploading artifact: $EFI_FILENAME_PREFIX-$version.efi"
    # This would be called from the workflow, not from script
    echo "artifact_name=$EFI_FILENAME_PREFIX-$version.efi"
    echo "artifact_path=buildout/ipxe/$EFI_FILENAME_PREFIX-$version.efi"
    echo "retention_days=$retention_days"
}

# Workflow functions
run_pr_workflow() {
    log_info "Running PR workflow..."
    
    # Get commit hash
    local commit_hash=$(git rev-parse --short HEAD)
    log_info "Commit hash: $commit_hash"
    
    # Build EFI
    build_efi $commit_hash
    
    log_success "PR workflow completed!"
    echo "version=$commit_hash"
}

run_release_workflow() {
    local version_type=${1:-"minor"}
    log_info "Running release workflow (type: $version_type)..."
    
    # Get version
    local version_output=$(get_version $version_type)
    local version=$(echo $version_output | grep "version=" | cut -d'=' -f2)
    
    # Build EFI
    build_efi $version
    
    # Create release
    if [ "$version_type" = "minor" ]; then
        create_release "$version" "$version" "$DRAFT_RELEASE_NOTES" "true" "true"
    else
        create_release "$version" "$version" "$DEFAULT_RELEASE_NOTES" "false" "false"
    fi
    
    log_success "Release workflow completed!"
    echo "version=$version"
}

# Main function for direct execution
main() {
    local command=${1:-"help"}
    
    case $command in
        "build")
            local version=${2:-"commit-hash"}
            local platform=${3:-"$DOCKER_PLATFORM"}
            build_efi $version $platform
            ;;
        "version")
            local type=${2:-"minor"}
            get_version $type
            ;;
        "release")
            local type=${2:-"minor"}
            run_release_workflow $type
            ;;
        "pr")
            run_pr_workflow
            ;;
        "test")
            local python_version=${2:-"$PYTHON_VERSION"}
            local ansible_version=${3:-"$ANSIBLE_VERSION"}
            local ansible_lint_version=${4:-"$ANSIBLE_LINT_VERSION"}
            test_ansible $python_version $ansible_version $ansible_lint_version
            ;;
        "help"|*)
            echo "Usage: $0 [command] [options...]"
            echo ""
            echo "Commands:"
            echo "  build [version] [platform]                    - Build EFI bootloader"
            echo "  version [type]                                - Get semantic version (minor/major)"
            echo "  release [type]                                - Run full release workflow"
            echo "  pr                                            - Run PR workflow"
            echo "  test [python] [ansible] [ansible-lint]       - Run Ansible tests"
            echo "  help                                          - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 build v1.0.0 linux/amd64"
            echo "  $0 version minor"
            echo "  $0 release major"
            echo "  $0 pr"
            echo "  $0 test 3.13 10.2.0 24.7.0"
            echo ""
            echo "Single-line examples:"
            echo "  $0 build v1.0.0 linux/amd64"
            echo "  $0 version minor"
            echo "  $0 release major"
            echo "  $0 pr"
            echo "  $0 test 3.13 10.2.0 24.7.0"
            ;;
    esac
}

# If script is executed directly, run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 