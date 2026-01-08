#!/bin/bash
set -e  # Exit on error

# ============================================================================
# Docker 离线安装脚本
# 支持 x86_64 和 aarch64 架构
# ============================================================================

# Color and style settings
readonly COLOR_YELLOW="\033[1;33m"
readonly COLOR_GREEN="\033[1;32m"
readonly COLOR_RED="\033[1;31m"
readonly COLOR_RESET="\033[0m"

# Unicode icons
readonly ICON_INFO="ℹ️"
readonly ICON_SUCCESS="✅"
readonly ICON_WARNING="⚠️"

# ============================================================================
# Utility Functions
# ============================================================================

print_log() {
    local message="$1"
    local color="${2:-$COLOR_RESET}"
    local icon="${3:-$ICON_INFO}"
    echo -e "${color}${icon} $(date '+%Y-%m-%d %H:%M:%S') - ${message}${COLOR_RESET}"
}

print_info() { print_log "$1" "$COLOR_YELLOW" "$ICON_INFO"; }
print_success() { print_log "$1" "$COLOR_GREEN" "$ICON_SUCCESS"; }
print_error() { print_log "$1" "$COLOR_RED" "$ICON_WARNING"; }

error_exit() {
    print_error "$1"
    exit "${2:-1}"
}

# ============================================================================
# Environment Detection
# ============================================================================

detect_base_dir() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Priority: 1. Parent dir 2. packages/ subdir 3. Same dir 4. Current dir
    if ls "$script_dir"/../docker-*.tgz &>/dev/null; then
        echo "$(cd "$script_dir/.." && pwd)"
    elif ls "$script_dir"/packages/docker-*.tgz &>/dev/null; then
        echo "$script_dir/packages"
    elif ls "$script_dir"/docker-*.tgz &>/dev/null; then
        echo "$script_dir"
    else
        echo "$(pwd)"
    fi
}

detect_arch() {
    case "$(uname -m)" in
        x86_64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) error_exit "Unsupported architecture: $(uname -m)" ;;
    esac
}

detect_services_dir() {
    local base_dir="$1"
    local candidates=(
        "$base_dir/services"
        "$(dirname "$base_dir")/services"
        "../services"
        "./services"
    )
    
    for dir in "${candidates[@]}"; do
        [[ -d "$dir" ]] && { echo "$dir"; return 0; }
    done
    
    return 1
}

# ============================================================================
# Version Management
# ============================================================================

extract_version() {
    local filename="$1"
    # Extract version pattern: X.Y.Z
    if [[ $filename =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0.0.0"
    fi
}

find_latest_file() {
    local pattern="$1"
    local latest_file=""
    local latest_version="0.0.0"
    
    for file in $pattern; do
        [[ ! -f "$file" ]] && continue
        
        local version=$(extract_version "$(basename "$file")")
        if [[ $(printf '%s\n' "$version" "$latest_version" | sort -V | tail -n1) == "$version" ]]; then
            latest_version="$version"
            latest_file="$file"
        fi
    done
    
    echo "$latest_file"
}

# ============================================================================
# Podman Cleanup (Optional)
# ============================================================================

cleanup_podman() {
    if ! command -v podman &>/dev/null; then
        print_info "Podman not installed, skipping cleanup"
        return 0
    fi
    
    print_info "Podman detected, starting cleanup..."
    
    # Stop and remove containers
    podman stop --all &>/dev/null || true
    podman rm --all &>/dev/null || true
    podman rmi --all &>/dev/null || true
    
    # Uninstall packages
    if command -v yum &>/dev/null; then
        yum remove -y podman podman-cni-config &>/dev/null || true
    elif command -v apt-get &>/dev/null; then
        apt-get remove -y podman &>/dev/null || true
    fi
    
    # Clean up data directories
    rm -rf /var/lib/podman /var/lib/containers ~/.local/share/podman &>/dev/null || true
    
    print_success "Podman cleanup completed"
}

# ============================================================================
# Docker Installation
# ============================================================================

install_docker_binaries() {
    local base_dir="$1"
    local arch="$2"
    
    print_info "Searching for Docker binaries (${arch})..."
    
    local docker_file=$(find_latest_file "$base_dir/docker-*-${arch}.tgz")
    [[ -z "$docker_file" ]] && error_exit "No Docker binary found for ${arch} in ${base_dir}"
    
    print_info "Installing Docker from $(basename "$docker_file")..."
    
    tar xzf "$docker_file" -C /tmp || error_exit "Failed to extract Docker archive"
    cp -f /tmp/docker/* /usr/bin/ || error_exit "Failed to copy Docker binaries"
    rm -rf /tmp/docker
    
    print_success "Docker binaries installed"
}

install_docker_compose() {
    local base_dir="$1"
    local arch="$2"
    
    print_info "Searching for Docker Compose binary (${arch})..."
    
    local compose_file=$(find_latest_file "$base_dir/docker-compose-linux-*-${arch}")
    [[ -z "$compose_file" ]] && error_exit "No Docker Compose binary found for ${arch} in ${base_dir}"
    
    print_info "Installing Docker Compose from $(basename "$compose_file")..."
    
    cp -f "$compose_file" /usr/bin/docker-compose || error_exit "Failed to copy Docker Compose"
    chmod +x /usr/bin/docker-compose
    
    print_success "Docker Compose installed"
}

install_rootless_extras() {
    local base_dir="$1"
    local arch="$2"
    
    print_info "Searching for Docker rootless extras (${arch})..."
    
    local rootless_file=$(find_latest_file "$base_dir/docker-rootless-extras-*-${arch}.tgz")
    if [[ -z "$rootless_file" ]]; then
        print_info "No rootless extras found, skipping"
        return 0
    fi
    
    print_info "Installing rootless extras from $(basename "$rootless_file")..."
    
    tar xzf "$rootless_file" -C /tmp || error_exit "Failed to extract rootless extras"
    
    if [[ -d "/tmp/docker" ]]; then
        cp -f /tmp/docker/* /usr/bin/
    else
        tar xzf "$rootless_file" -C /tmp --strip-components=1 || error_exit "Failed to extract rootless extras"
        cp -f /tmp/rootlesskit* /tmp/vpnkit /usr/bin/ 2>/dev/null || true
    fi
    
    rm -rf /tmp/docker /tmp/rootlesskit* /tmp/vpnkit
    
    print_success "Rootless extras installed"
}

# ============================================================================
# Docker Configuration
# ============================================================================

setup_docker_services() {
    local services_dir="$1"
    
    print_info "Configuring Docker services..."
    
    mkdir -p /etc/docker || error_exit "Failed to create /etc/docker"
    
    # Copy service files
    cp -f "$services_dir/containerd.service" /usr/lib/systemd/system/ || error_exit "Failed to copy containerd.service"
    cp -f "$services_dir/daemon.json" /etc/docker/ || error_exit "Failed to copy daemon.json"
    cp -f "$services_dir/docker.service" /usr/lib/systemd/system/ || error_exit "Failed to copy docker.service"
    cp -f "$services_dir/docker.socket" /usr/lib/systemd/system/ || error_exit "Failed to copy docker.socket"
    
    systemctl daemon-reload
    
    # Start containerd
    print_info "Starting containerd service..."
    systemctl enable containerd &>/dev/null || error_exit "Failed to enable containerd"
    systemctl start containerd || error_exit "Failed to start containerd. Check: systemctl status containerd"
    
    # Start docker
    print_info "Starting Docker service..."
    systemctl enable docker &>/dev/null || error_exit "Failed to enable Docker"
    systemctl start docker || error_exit "Failed to start Docker. Check: systemctl status docker"
    
    print_success "Docker services configured and started"
}

configure_docker_user() {
    print_info "Configuring Docker user and group..."
    
    # Create docker group if not exists
    if ! getent group docker &>/dev/null; then
        groupadd docker
        print_info "Docker group created"
    fi
    
    # Create dockeruser if not exists
    if ! id dockeruser &>/dev/null; then
        useradd -m -g docker dockeruser
        print_info "Docker user 'dockeruser' created"
    fi
    
    # Add current user to docker group
    local current_user="$(whoami)"
    if ! id -nG "$current_user" | grep -qw "docker"; then
        usermod -aG docker "$current_user"
        print_info "User '$current_user' added to docker group (logout required)"
    fi
    
    print_success "Docker user configured"
}

# ============================================================================
# System Verification
# ============================================================================

verify_installation() {
    print_info "Verifying Docker installation..."
    
    # Check service status
    systemctl is-active docker &>/dev/null || error_exit "Docker service is not running"
    systemctl is-enabled docker &>/dev/null || error_exit "Docker service is not enabled"
    
    # Get version info
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "N/A")
    local compose_version=$(docker-compose version --short 2>/dev/null || echo "N/A")
    local containerd_version=$(containerd --version 2>/dev/null | awk '{print $3}' || echo "N/A")
    local runc_version=$(runc --version 2>/dev/null | head -1 | awk '{print $3}' || echo "N/A")
    
    print_success "Docker version: $docker_version"
    print_success "Docker Compose version: $compose_version"
    print_success "containerd version: $containerd_version"
    print_success "runc version: $runc_version"
}

# ============================================================================
# Main Installation Flow
# ============================================================================

main() {
    # Check root privileges
    [[ $EUID -ne 0 ]] && error_exit "This script must be run as root"
    
    print_info "Starting Docker installation..."
    
    # Detect environment
    local BASE_DIR=$(detect_base_dir)
    local ARCH=$(detect_arch)
    
    print_info "Base directory: $BASE_DIR"
    print_info "Architecture: $ARCH"
    
    # Find services directory
    local SERVICES_DIR=$(detect_services_dir "$BASE_DIR")
    [[ -z "$SERVICES_DIR" ]] && error_exit "Services directory not found"
    
    # Cleanup podman if exists
    cleanup_podman
    
    # Install components
    install_docker_binaries "$BASE_DIR" "$ARCH"
    install_docker_compose "$BASE_DIR" "$ARCH"
    install_rootless_extras "$BASE_DIR" "$ARCH"
    
    # Configure Docker
    configure_docker_user
    setup_docker_services "$SERVICES_DIR"
    
    # Verify installation
    verify_installation
    
    echo ""
    print_success "Docker installation completed successfully!"
    print_info "Note: If you were added to docker group, run 'newgrp docker' or logout/login"
}

# Execute main function
main "$@"