#!/bin/bash
# SSHp installer. install, update, and uninstall behave as they did in 3.x.
# Version: 4.0.0

set -euo pipefail

VERSION="4.0.1"
RAW_URL="https://raw.githubusercontent.com/abhinav937/sshp/main/sshp"
INSTALL_PATH="$HOME/.local/bin/sshp"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

shell_rc() {
    if [[ "${SHELL:-}" == *zsh* ]]; then
        echo "$HOME/.zshrc"
    else
        echo "$HOME/.bashrc"
    fi
}

show_help() {
    cat << EOF
SSHp Tool - Unified Manager

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  install, i     Install SSHp tool
  uninstall, u   Uninstall SSHp tool
  update, up     Update SSHp tool
  status, s      Show installation status
  help, h        Show this help message

Options:
  --force, -f    Force operation without prompts
  --keep-config  Keep SSH configuration files (uninstall only)

Examples:
  $0 install
  $0 update
  $0 uninstall
  $0 install --force
  $0 uninstall --keep-config

One-line commands:
  bash <(curl -s https://raw.githubusercontent.com/abhinav937/sshp/main/sshp-manager.sh) install
  bash <(curl -s https://raw.githubusercontent.com/abhinav937/sshp/main/sshp-manager.sh) update
  bash <(curl -s https://raw.githubusercontent.com/abhinav937/sshp/main/sshp-manager.sh) uninstall
EOF
}

local_tool_path() {
    local source="${BASH_SOURCE[0]:-}"
    local dir
    if [[ -z "$source" || ! -f "$source" ]]; then
        return 1
    fi
    dir=$(cd "$(dirname "$source")" 2>/dev/null && pwd) || return 1
    if [[ -f "$dir/sshp" ]]; then
        echo "$dir/sshp"
        return 0
    fi
    return 1
}

install_tool() {
    local src dest_dir
    dest_dir=$(dirname "$INSTALL_PATH")
    mkdir -p "$dest_dir"
    if src=$(local_tool_path); then
        print_status "Installing from $src"
        cp "$src" "$INSTALL_PATH"
    else
        if ! command -v curl >/dev/null 2>&1; then
            print_error "curl is required to download sshp"
            return 1
        fi
        print_status "Downloading $RAW_URL"
        curl -fsSL "$RAW_URL" -o "$INSTALL_PATH"
    fi
    chmod +x "$INSTALL_PATH"
}

add_alias() {
    local rc
    rc=$(shell_rc)
    touch "$rc"
    if grep -q '^alias sshp=' "$rc"; then
        print_status "sshp alias already present in $rc"
        return 0
    fi
    printf '\n# SSHp Tool alias\nalias sshp="%s"\n' "$INSTALL_PATH" >> "$rc"
    print_success "SSHp alias added to $rc"
}

remove_alias() {
    local rc backup
    rc=$(shell_rc)
    if [[ ! -f "$rc" ]]; then
        print_warning "Shell configuration file not found: $rc"
        return 0
    fi
    if ! grep -q '^alias sshp=' "$rc"; then
        print_warning "SSHp alias not found in $rc"
        return 0
    fi
    backup="$rc.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$rc" "$backup"
    grep -v -e '^# SSHp Tool alias$' -e '^alias sshp=' "$rc" > "$rc.tmp" || true
    mv "$rc.tmp" "$rc"
    print_success "SSHp alias removed from $rc"
    print_status "Backup created: $backup"
}

remove_configs() {
    if [[ "${KEEP_CONFIG:-false}" == "true" ]]; then
        print_status "Keeping SSH configuration files (--keep-config specified)"
        return 0
    fi
    local config
    for config in ".sshp_config.json" "$HOME/.sshp_config.json"; do
        if [[ -f "$config" ]]; then
            rm -f "$config"
            print_success "SSH configuration file removed: $config"
        fi
    done
}

confirm_operation() {
    local operation="$1"
    if [[ "${FORCE:-false}" == "true" ]]; then
        return 0
    fi
    echo "SSHp Tool - $operation"
    echo "Version: $VERSION"
    case "$operation" in
        Install)
            echo "Install to $INSTALL_PATH and add a shell alias if one is missing"
            ;;
        Update)
            echo "Replace $INSTALL_PATH. Configuration files stay where they are."
            ;;
        Uninstall)
            echo "Remove the tool and the shell alias"
            if [[ "${KEEP_CONFIG:-false}" != "true" ]]; then
                echo "Remove configuration files"
            fi
            ;;
    esac
    echo ""
    local reply
    read -r -p "Continue? (y/N) " reply
    if [[ ! "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        print_status "$operation cancelled"
        exit 0
    fi
}

install_sshp() {
    print_status "Installing SSHp tool..."
    install_tool
    add_alias
    echo ""
    print_success "SSHp tool has been installed successfully."
    print_status "Binary: $INSTALL_PATH"
    print_status "To get started, run: sshp --help"
    print_status "To setup SSH configuration, run: sshp --setup"
}

update_sshp() {
    if [[ ! -f "$INSTALL_PATH" ]]; then
        print_warning "SSHp tool is not installed. Installing instead..."
        install_sshp
        return 0
    fi
    print_status "Updating SSHp tool..."
    install_tool
    echo ""
    print_success "SSHp tool has been updated successfully."
    print_status "Your existing configuration has been preserved."
    print_status "To verify the update, run: sshp --version"
}

uninstall_sshp() {
    print_status "Uninstalling SSHp tool..."
    if [[ -f "$INSTALL_PATH" ]]; then
        rm -f "$INSTALL_PATH"
        print_success "SSHp tool removed from $INSTALL_PATH"
    else
        print_warning "SSHp tool not found at $INSTALL_PATH"
    fi
    if [[ -d "$HOME/.local/bin" && -z "$(ls -A "$HOME/.local/bin")" ]]; then
        rmdir "$HOME/.local/bin"
        print_status "Removed empty ~/.local/bin directory"
    fi
    remove_alias
    remove_configs
    echo ""
    print_success "SSHp tool has been uninstalled"
}

installed_version() {
    if [[ ! -f "$INSTALL_PATH" ]]; then
        echo "not installed"
        return 0
    fi
    local version
    version=$(awk -F'"' '/^VERSION = / { print $2; exit }' "$INSTALL_PATH")
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        echo "unknown"
    fi
}

check_installation_status() {
    local rc
    rc=$(shell_rc)
    echo "Installation Status:"
    echo "==================="
    echo ""
    if [[ -x "$INSTALL_PATH" ]]; then
        print_success "SSHp script found at: $INSTALL_PATH"
    elif [[ -f "$INSTALL_PATH" ]]; then
        print_warning "SSHp script is not executable: $INSTALL_PATH"
    else
        print_warning "SSHp script not found at: $INSTALL_PATH"
    fi
    print_status "Version: $(installed_version)"
    if [[ -f "$rc" ]] && grep -q '^alias sshp=' "$rc"; then
        print_success "SSHp alias found in: $rc"
    else
        print_status "SSHp alias not found in: $rc (not required when ~/.local/bin is on PATH)"
    fi
    if command -v sshp >/dev/null 2>&1; then
        print_success "sshp command is accessible"
    else
        print_warning "sshp command is not accessible from this shell"
    fi
    if command -v rsync >/dev/null 2>&1; then
        print_success "rsync is available"
    else
        print_status "rsync not found (scp will be used)"
    fi
    local config found=false
    for config in ".sshp_config.json" "$HOME/.sshp_config.json"; do
        if [[ -f "$config" ]]; then
            print_success "SSH configuration found: $config"
            found=true
        fi
    done
    if [[ "$found" == "false" ]]; then
        print_warning "No SSH configuration files found"
    fi
}

COMMAND=""
FORCE=false
KEEP_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        install|i) COMMAND="install"; shift ;;
        uninstall|u) COMMAND="uninstall"; shift ;;
        update|up) COMMAND="update"; shift ;;
        status|s) COMMAND="status"; shift ;;
        help|h|--help) show_help; exit 0 ;;
        --force|-f) FORCE=true; shift ;;
        --keep-config) KEEP_CONFIG=true; shift ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

case "$COMMAND" in
    install)
        confirm_operation "Install"
        install_sshp
        ;;
    uninstall)
        confirm_operation "Uninstall"
        uninstall_sshp
        ;;
    update)
        confirm_operation "Update"
        update_sshp
        ;;
    status)
        check_installation_status
        ;;
    "")
        show_help
        exit 1
        ;;
esac
