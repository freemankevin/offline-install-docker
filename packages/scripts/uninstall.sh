#!/bin/bash
set -e  # Exit on error

# ============================================================================
# Docker 卸载脚本
# 完全清理 Docker、Docker Compose 及相关配置
# ============================================================================

# Color settings
readonly COLOR_YELLOW="\033[1;33m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_RESET="\033[0m"

# Icons
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
print_warning() { print_log "$1" "$COLOR_RED" "$ICON_WARNING"; }

# ============================================================================
# Service Management
# ============================================================================

stop_docker_services() {
    print_info "Stopping Docker services..."
    
    # Stop services gracefully
    systemctl stop docker.socket &>/dev/null || true
    systemctl stop docker &>/dev/null || true
    systemctl stop containerd &>/dev/null || true
    
    # Disable autostart
    systemctl disable docker.socket &>/dev/null || true
    systemctl disable docker &>/dev/null || true
    systemctl disable containerd &>/dev/null || true
    
    print_success "Docker services stopped and disabled"
}

# ============================================================================
# Binary Cleanup
# ============================================================================

remove_docker_binaries() {
    print_info "Removing Docker binaries..."
    
    local binaries=(
        "docker"
        "dockerd"
        "docker-init"
        "docker-proxy"
        "containerd"
        "containerd-shim"
        "containerd-shim-runc-v2"
        "ctr"
        "runc"
        "rootlesskit"
        "rootlesskit-docker-proxy"
        "vpnkit"
    )
    
    for bin in "${binaries[@]}"; do
        rm -f "/usr/bin/${bin}" "/usr/local/bin/${bin}" &>/dev/null || true
    done
    
    # Remove docker-compose
    rm -f /usr/bin/docker-compose /usr/local/bin/docker-compose &>/dev/null || true
    
    print_success "Docker binaries removed"
}

# ============================================================================
# Configuration Cleanup
# ============================================================================

remove_systemd_units() {
    print_info "Removing systemd units..."
    
    local service_dirs=(
        "/usr/lib/systemd/system"
        "/etc/systemd/system"
        "/lib/systemd/system"
    )
    
    local patterns=(
        "*docker*.service"
        "*docker*.socket"
        "*containerd*.service"
    )
    
    for dir in "${service_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        for pattern in "${patterns[@]}"; do
            find "$dir" -maxdepth 1 -name "$pattern" -type f -delete 2>/dev/null || true
        done
    done
    
    # Remove service directories
    rm -rf /etc/systemd/system/docker.service.d &>/dev/null || true
    
    systemctl daemon-reload
    
    print_success "Systemd units removed"
}

remove_config_files() {
    print_info "Removing configuration files..."
    
    # Remove Docker config directory
    rm -rf /etc/docker &>/dev/null || true
    
    # Remove other potential config locations
    rm -f /etc/default/docker &>/dev/null || true
    rm -f /etc/sysconfig/docker &>/dev/null || true
    
    print_success "Configuration files removed"
}

# ============================================================================
# User/Group Cleanup
# ============================================================================

remove_docker_user_group() {
    print_info "Removing Docker user and group..."
    
    # Remove dockeruser
    if id dockeruser &>/dev/null; then
        userdel -r dockeruser &>/dev/null || true
        print_info "Docker user 'dockeruser' removed"
    fi
    
    # Remove docker group
    if getent group docker &>/dev/null; then
        groupdel docker &>/dev/null || true
        print_info "Docker group removed"
    fi
    
    print_success "User and group cleanup completed"
}

# ============================================================================
# Data Cleanup
# ============================================================================

remove_docker_data() {
    print_info "Removing Docker data directories..."
    
    # Known Docker data locations
    local data_dirs=(
        "/var/lib/docker"
        "/var/lib/containerd"
        "/var/lib/dockershim"
        "/var/run/docker"
        "/var/run/docker.sock"
        "/run/docker"
        "/run/docker.sock"
    )
    
    for dir in "${data_dirs[@]}"; do
        if [[ -e "$dir" ]]; then
            rm -rf "$dir" &>/dev/null || true
            print_info "Removed: $dir"
        fi
    done
    
    # Check for Docker directories in common locations
    for location in /var/lib /data; do
        if [[ -d "$location" ]]; then
            local docker_dir="${location}/docker"
            if [[ -d "$docker_dir" ]]; then
                rm -rf "$docker_dir" &>/dev/null || true
                print_info "Removed: $docker_dir"
            fi
        fi
    done
    
    print_success "Docker data directories removed"
}

# ============================================================================
# Security Settings Cleanup
# ============================================================================

cleanup_security_settings() {
    print_info "Cleaning up security settings..."
    
    # Remove Docker environment variables from common shell configs
    local shell_configs=(
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.zshrc"
        "$HOME/.profile"
    )
    
    for config in "${shell_configs[@]}"; do
        if [[ -f "$config" ]]; then
            sed -i '/DOCKER_CONTENT_TRUST=1/d' "$config" 2>/dev/null || true
            sed -i '/DOCKER_HOST=/d' "$config" 2>/dev/null || true
        fi
    done
    
    print_success "Security settings cleaned up"
}

# ============================================================================
# Verification
# ============================================================================

verify_removal() {
    print_info "Verifying Docker removal..."
    
    local issues=()
    
    # Check for remaining binaries
    if command -v docker &>/dev/null; then
        issues+=("docker binary still exists")
    fi
    
    # Check for running services
    if systemctl is-active docker &>/dev/null; then
        issues+=("docker service still running")
    fi
    
    # Check for remaining data
    if [[ -d "/var/lib/docker" ]]; then
        issues+=("/var/lib/docker still exists")
    fi
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        print_warning "Some cleanup issues detected:"
        for issue in "${issues[@]}"; do
            print_warning "  - $issue"
        done
        return 1
    fi
    
    print_success "Docker has been completely removed"
    return 0
}

# ============================================================================
# Main Uninstallation Flow
# ============================================================================

main() {
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        print_warning "This script must be run as root"
        exit 1
    fi
    
    print_warning "Starting Docker uninstallation..."
    echo ""
    
    # Confirm with user
    read -p "This will completely remove Docker and all its data. Continue? (y/N): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Uninstallation cancelled"
        exit 0
    fi
    
    # Execute removal steps
    stop_docker_services
    remove_docker_binaries
    remove_systemd_units
    remove_config_files
    remove_docker_user_group
    remove_docker_data
    cleanup_security_settings
    
    echo ""
    
    # Verify removal
    if verify_removal; then
        print_success "Docker has been completely uninstalled!"
    else
        print_warning "Docker uninstallation completed with warnings (see above)"
        exit 1
    fi
}

# Execute main function
main "$@"