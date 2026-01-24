#!/bin/bash

# SSHp Tool - Unified Manager Script
# Version: 3.5.2 - Handles install, uninstall, and update operations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS for compatibility
detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*)  echo "linux" ;;
        FreeBSD*) echo "freebsd" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

OS_TYPE=$(detect_os)

# Cross-platform sed in-place edit
sed_inplace() {
    if [[ "$OS_TYPE" == "macos" ]] || [[ "$OS_TYPE" == "freebsd" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Cross-platform stat for file size
get_file_size() {
    local file="$1"
    if [[ "$OS_TYPE" == "macos" ]] || [[ "$OS_TYPE" == "freebsd" ]]; then
        stat -f%z "$file" 2>/dev/null || echo "unknown"
    else
        stat -c%s "$file" 2>/dev/null || echo "unknown"
    fi
}

# Cross-platform stat for modification date
get_file_date() {
    local file="$1"
    if [[ "$OS_TYPE" == "macos" ]] || [[ "$OS_TYPE" == "freebsd" ]]; then
        stat -f%Sm -t%Y-%m-%d "$file" 2>/dev/null || echo "unknown"
    else
        stat -c%y "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown"
    fi
}

# Function to show help
show_help() {
    echo "SSHp Tool - Unified Manager"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  install, i     Install SSHp tool"
    echo "  uninstall, u   Uninstall SSHp tool"
    echo "  update, up     Update SSHp tool"
    echo "  status, s      Show installation status"
    echo "  help, h        Show this help message"
    echo ""
    echo "Options:"
    echo "  --force, -f    Force operation without prompts"
    echo "  --keep-config  Keep SSH configuration files (uninstall only)"
    echo ""
    echo "Examples:"
    echo "  $0 install                    # Install SSHp tool"
    echo "  $0 update                     # Update SSHp tool"
    echo "  $0 uninstall                  # Uninstall SSHp tool"
    echo "  $0 install --force            # Force install without prompts"
    echo "  $0 uninstall --keep-config   # Uninstall but keep SSH config"
    echo ""
    echo "One-line commands:"
    echo "  bash <(curl -s https://raw.githubusercontent.com/abhinav937/sshp/main/sshp-manager.sh) install"
    echo "  bash <(curl -s https://raw.githubusercontent.com/abhinav937/sshp/main/sshp-manager.sh) update"
    echo "  bash <(curl -s https://raw.githubusercontent.com/abhinav937/sshp/main/sshp-manager.sh) uninstall"
}

# Function to output the sshp script content
output_sshp_script() {
    cat << 'EOF'
#!/usr/bin/env python3
"""
SSHp Tool - Self-contained script for pushing files to remote devices
Version: 3.5.2

Features:
- Push/pull files via SCP or rsync
- Recursive directory support
- Compression option
- Dry-run mode
- Progress indicators
- Cross-platform (Linux, macOS, FreeBSD, Windows WSL)
"""

import os
import sys
import json
import argparse
import subprocess
import getpass
import re
import shutil
import tempfile
import time
from pathlib import Path


def validate_hostname(hostname):
    """Validate hostname format (user@host or just host)"""
    # Pattern for user@host or just host/IP
    pattern = r'^([a-zA-Z0-9_-]+@)?([a-zA-Z0-9.-]+|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$'
    if not re.match(pattern, hostname):
        return False, "Invalid hostname format. Use 'user@host' or 'host/IP'"
    return True, ""


def validate_port(port):
    """Validate port number"""
    try:
        port_int = int(port)
        if 1 <= port_int <= 65535:
            return True, port_int
        return False, "Port must be between 1 and 65535"
    except ValueError:
        return False, "Port must be a number"


def validate_path(path):
    """Validate and sanitize remote path"""
    # Prevent command injection
    dangerous_chars = [';', '&', '|', '$', '`', '(', ')', '{', '}', '<', '>', '\n', '\r']
    for char in dangerous_chars:
        if char in path:
            return False, f"Invalid character '{char}' in path"
    return True, ""


class SSHpTool:
    def __init__(self):
        self.local_config_file = ".sshp_config.json"
        self.global_config_file = os.path.expanduser("~/.sshp_config.json")
        self.config, self.config_source = self.load_config()
        self.has_rsync = shutil.which('rsync') is not None
        # Flags for forcing global/local setup
        self._setup_force_global = False
        self._setup_force_local = False

    def load_config(self):
        """Load SSH configuration from local file, falling back to global config"""
        # Try local config first
        if os.path.exists(self.local_config_file):
            try:
                with open(self.local_config_file, 'r') as f:
                    return json.load(f), "local"
            except (json.JSONDecodeError, IOError):
                pass

        # Fall back to global config
        if os.path.exists(self.global_config_file):
            try:
                with open(self.global_config_file, 'r') as f:
                    return json.load(f), "global"
            except (json.JSONDecodeError, IOError):
                pass

        return None, None

    def save_config(self, config, save_global=False):
        """Save SSH configuration to file"""
        config_file = self.global_config_file if save_global else self.local_config_file
        try:
            with open(config_file, 'w') as f:
                json.dump(config, f, indent=2)
            config_type = "global" if save_global else "local"
            print(f"Configuration saved to {config_file} ({config_type})")
            return True
        except IOError as e:
            print(f"Error saving configuration: {e}")
            return False

    def setup_ssh_key(self, hostname, port=22):
        """Setup SSH key for passwordless authentication"""
        print("Setting up SSH key...")

        # Check if SSH key already exists
        default_key_path = os.path.expanduser("~/.ssh/id_rsa")
        if os.path.exists(default_key_path):
            print(f"Found existing key at {default_key_path}")
            use_existing = input("Use existing key? (Y/n): ").strip().lower()
            if use_existing in ['', 'y', 'yes']:
                return default_key_path
            else:
                print("Generating new key...")

        try:
            # Create .ssh directory if it doesn't exist
            ssh_dir = os.path.expanduser("~/.ssh")
            os.makedirs(ssh_dir, mode=0o700, exist_ok=True)

            # Generate new SSH key
            try:
                # Check if key already exists and remove it first
                if os.path.exists(default_key_path):
                    os.remove(default_key_path)
                if os.path.exists(f"{default_key_path}.pub"):
                    os.remove(f"{default_key_path}.pub")

                # Generate key with proper input sequence
                result = subprocess.run([
                    "ssh-keygen", "-t", "rsa", "-b", "4096", "-f", default_key_path, "-N", ""
                ], capture_output=True, text=True, timeout=30)

                if result.returncode == 0:
                    print(f"Key generated at {default_key_path}")
                    return default_key_path
                else:
                    print(f"Failed to generate key: {result.stderr}")
                    return None
            except subprocess.TimeoutExpired:
                print("Key generation timed out.")
                return None
            except OSError as e:
                print(f"Error generating key: {e}")
                return None

        except OSError as e:
            print(f"Error generating SSH key: {e}")
            print("Please generate SSH key manually:")
            print(f"ssh-keygen -t rsa -b 4096 -f {default_key_path}")
            return None

    def copy_ssh_key_to_remote(self, hostname, key_path, port=22):
        """Copy SSH public key to remote machine"""
        print(f"Copying key to {hostname}...")
        print("Enter your remote machine password when prompted.")

        try:
            # Use ssh-copy-id to copy the public key (allow interactive input)
            result = subprocess.run([
                "ssh-copy-id", "-p", str(port),
                "-i", f"{key_path}.pub", hostname
            ], timeout=60)  # Allow interactive input with reasonable timeout

            if result.returncode == 0:
                print("Key copied successfully!")
                print("Passwordless authentication ready.")
                return True
            else:
                print("Failed to copy key.")
                print("You may need to copy manually or check connection.")
                return False
        except subprocess.TimeoutExpired:
            print("Key copy timed out.")
            return False
        except OSError as e:
            print(f"Error copying key: {e}")
            return False

    def setup_config(self, existing_config=None):
        """Interactive setup of SSH configuration"""
        print("SSHp Tool Configuration Setup")
        print("==================================")

        if existing_config:
            print("Press Enter to keep current values (shown in brackets).")
            print("")

        config = existing_config.copy() if existing_config else {}

        # Hostname with validation
        while True:
            default_host = config.get('hostname', '')
            prompt = f"Remote hostname/IP [{default_host}]: " if default_host else "Remote hostname/IP (e.g., pi@192.168.1.100): "
            hostname = input(prompt).strip()
            
            if not hostname and default_host:
                hostname = default_host

            if hostname:
                valid, error = validate_hostname(hostname)
                if valid:
                    config['hostname'] = hostname
                    break
                print(f"Error: {error}")
            else:
                print("Hostname is required.")

        # Port with validation
        while True:
            default_port = config.get('port', 22)
            port = input(f"SSH port (default: {default_port}): ").strip()
            if not port:
                config['port'] = default_port
                break
            valid, result = validate_port(port)
            if valid:
                config['port'] = result
                break
            print(f"Error: {result}")

        # Remote directory with validation
        while True:
            default_dir = config.get('remote_dir', '~')
            remote_dir = input(f"Remote working directory (default: {default_dir}): ").strip()
            if not remote_dir:
                config['remote_dir'] = default_dir
                break
            valid, error = validate_path(remote_dir)
            if valid:
                config['remote_dir'] = remote_dir
                break
            print(f"Error: {error}")

        # Transfer method (scp or rsync)
        if self.has_rsync:
            while True:
                default_method = config.get('transfer_method', 'rsync')
                method = input(f"Transfer method (scp/rsync) [{default_method}]: ").strip().lower()
                if not method:
                    method = default_method
                if method in ["scp", "rsync"]:
                    config['transfer_method'] = method
                    break
                print("Please choose 'scp' or 'rsync'.")
        else:
            config['transfer_method'] = "scp"
            print("Note: rsync not found, using scp.")

        # Quiet mode
        while True:
            default_quiet = config.get('quiet_mode', False)
            quiet_str = "yes" if default_quiet else "no"
            quiet = input(f"Quiet mode (summary only) (yes/no) [{quiet_str}]: ").strip().lower()
            if not quiet:
                config['quiet_mode'] = default_quiet
                break
            if quiet in ['y', 'yes']:
                config['quiet_mode'] = True
                break
            elif quiet in ['n', 'no']:
                config['quiet_mode'] = False
                break
            print("Please answer yes or no.")

        # Authentication method
        while True:
            default_auth = config.get('auth_method', 'key')
            auth_method = input(f"Authentication method (key/password) [{default_auth}]: ").strip().lower()
            if not auth_method:
                auth_method = default_auth
            if auth_method in ["key", "password"]:
                config['auth_method'] = auth_method
                break
            print("Please choose 'key' or 'password'.")

        # SSH key setup for key authentication
        if auth_method == "key":
            default_key = config.get('key_path', '~/.ssh/id_rsa')
            key_path = input(f"SSH key path (default: {default_key}): ").strip()
            config['key_path'] = key_path if key_path else default_key

            # Offer to setup SSH key automatically
            setup_key = input("Setup SSH key for passwordless authentication? (Y/n): ").strip().lower()
            if setup_key in ['', 'y', 'yes']:
                key_path = self.setup_ssh_key(config['hostname'], config['port'])
                if key_path:
                    config['key_path'] = key_path

                    # Copy key to remote machine
                    copy_key = input("Copy SSH key to remote machine? (Y/n): ").strip().lower()
                    if copy_key in ['', 'y', 'yes']:
                        if self.copy_ssh_key_to_remote(config['hostname'], key_path, config['port']):
                            print("Key setup complete!")
                        else:
                            print("Key copy failed. You may need to copy manually.")
                    else:
                        print("Key not copied. You may need to copy manually later.")
                else:
                    print("Key setup failed. You can:")
                    print("1. Generate key manually: ssh-keygen -t rsa -b 4096")
                    print("2. Copy key manually: ssh-copy-id " + config['hostname'])
                    print("3. Continue without key setup (will use password authentication)")
            else:
                print("Key setup skipped. You can set up keys manually later.")

        # Ask where to save (unless force_global or force_local is set)
        if self._setup_force_global:
            save_global = True
        elif self._setup_force_local:
            save_global = False
        else:
            save_global = False
            save_choice = input("Save as global config (available everywhere)? (y/N): ").strip().lower()
            if save_choice in ['y', 'yes']:
                save_global = True

        if self.save_config(config, save_global=save_global):
            print("Configuration setup complete!")
            if save_global:
                print("This config will be used as fallback for all directories.")
            return True
        return False

    def setup_global_config(self):
        """Setup global SSH configuration directly"""
        print("Setting up GLOBAL SSH configuration")
        print("This will be saved to:", self.global_config_file)
        print("")
        self._setup_force_global = True
        self._setup_force_local = False
        return self.setup_config()

    def setup_local_config(self):
        """Setup local SSH configuration directly"""
        print("Setting up LOCAL SSH configuration")
        print("This will be saved to:", self.local_config_file)
        print("")
        self._setup_force_global = False
        self._setup_force_local = True
        return self.setup_config()

    def edit_config(self):
        """Edit existing configuration"""
        if not self.config:
            print("No configuration found. Run setup first.")
            return False

        print("Current configuration:")
        self.show_config()

        if input("Edit configuration? (y/N): ").lower() == 'y':
            return self.setup_config(existing_config=self.config)
        return True

    def show_config(self):
        """Show current configuration"""
        if not self.config:
            print("No SSH configuration found.")
            print("Run with --setup to create configuration.")
            print("")
            print("Config locations:")
            print(f"  Local:  ./{self.local_config_file}")
            print(f"  Global: {self.global_config_file}")
            return

        config_file = self.global_config_file if self.config_source == "global" else self.local_config_file
        print(f"Current SSH configuration ({self.config_source}: {config_file}):")
        print(f"  Hostname: {self.config.get('hostname', 'Not set')}")
        print(f"  Port: {self.config.get('port', 'Not set')}")
        print(f"  Remote Directory: {self.config.get('remote_dir', 'Not set')}")
        print(f"  Transfer Method: {self.config.get('transfer_method', 'scp')}")
        print(f"  Quiet Mode: {'Yes' if self.config.get('quiet_mode', False) else 'No'}")
        print(f"  Auth Method: {self.config.get('auth_method', 'Not set')}")
        if self.config.get('auth_method') == 'key':
            print(f"  SSH Key: {self.config.get('key_path', 'Not set')}")
        print(f"  Rsync Available: {'Yes' if self.has_rsync else 'No'}")

        # Show if there's also a local/global config available
        if self.config_source == "global" and os.path.exists(self.local_config_file):
            print(f"\n  Note: Local config also exists (would take priority)")
        elif self.config_source == "local" and os.path.exists(self.global_config_file):
            print(f"\n  Note: Global config also exists at {self.global_config_file}")

    def _build_ssh_base_cmd(self):
        """Build base SSH command with common options"""
        ssh_cmd = ["ssh"]

        if self.config.get('auth_method') == 'key':
            ssh_cmd.extend(["-i", os.path.expanduser(self.config['key_path'])])

        ssh_cmd.extend(["-p", str(self.config['port'])])
        ssh_cmd.append(self.config['hostname'])

        return ssh_cmd

    def test_connection(self):
        """Test SSH connection"""
        if not self.config:
            print("No configuration found. Run setup first.")
            return False

        print("Testing SSH connection...")

        ssh_cmd = self._build_ssh_base_cmd()
        ssh_cmd.append("exit")

        try:
            # simple check without capturing output to allow password prompt
            result = subprocess.run(ssh_cmd, timeout=10)
            if result.returncode == 0:
                print("SSH connection successful!")
                return True
            else:
                print("SSH connection failed.")
                return False
        except subprocess.TimeoutExpired:
            print("SSH connection timed out.")
            return False
        except OSError as e:
            print(f"SSH connection error: {e}")
            return False

    def list_remote_files(self):
        """List files in remote directory"""
        if not self.config:
            print("No configuration found. Run setup first.")
            return False

        print("Listing remote files...")
        print("Remote files:")
        print("-------------")

        ssh_cmd = self._build_ssh_base_cmd()
        ssh_cmd.append(f"ls -la {self.config['remote_dir']}")

        try:
            # Run without capturing output to allow password prompt
            result = subprocess.run(ssh_cmd, timeout=10)
            if result.returncode != 0:
                print("Failed to list remote files.")
        except OSError as e:
            print(f"Error listing remote files: {e}")

    def _build_scp_cmd(self, compress=False, recursive=False, verbose=False):
        """Build SCP command with options"""
        scp_cmd = ["scp"]

        if verbose:
            scp_cmd.append("-v")
        if compress:
            scp_cmd.append("-C")
        if recursive:
            scp_cmd.append("-r")

        if self.config.get('auth_method') == 'key':
            scp_cmd.extend(["-i", os.path.expanduser(self.config['key_path'])])

        scp_cmd.extend(["-P", str(self.config['port'])])

        return scp_cmd

    def _build_rsync_cmd(self, compress=False, verbose=False, dry_run=False):
        """Build rsync command with options"""
        rsync_cmd = ["rsync", "-a"]
        
        if not self.config.get('quiet_mode', False):
            rsync_cmd.append("--progress")

        if verbose:
            rsync_cmd.append("-v")
        if compress:
            rsync_cmd.append("-z")
        if dry_run:
            rsync_cmd.append("--dry-run")

        # Build SSH command for rsync
        ssh_opts = f"ssh -p {self.config['port']}"
        if self.config.get('auth_method') == 'key':
            ssh_opts += f" -i {os.path.expanduser(self.config['key_path'])}"

        rsync_cmd.extend(["-e", ssh_opts])

        return rsync_cmd

    def push_files(self, files, verbose=False, compress=False, recursive=False, dry_run=False):
        """Push files to remote device"""
        if not self.config:
            print("No configuration found. Run setup first.")
            return False

        if not files:
            print("No files specified to push.")
            return False

        # Validate files exist
        valid_files = []
        for f in files:
            if os.path.exists(f):
                valid_files.append(f)
            else:
                print(f"Warning: File not found: {f}")

        if not valid_files:
            print("No valid files to push.")
            return False

        # Check if any files are directories
        has_dirs = any(os.path.isdir(f) for f in valid_files)
        if has_dirs and not recursive:
            print("Warning: Directories found. Use --recursive (-r) to push directories.")
            recursive = True

        use_rsync = self.config.get('transfer_method', 'scp') == 'rsync' and self.has_rsync

        if dry_run:
            print(f"[DRY RUN] Would push {len(valid_files)} file(s) to remote device...")
        else:
            print(f"Pushing {len(valid_files)} file(s) to remote device...")

        try:
            if use_rsync:
                cmd = self._build_rsync_cmd(compress=compress, verbose=verbose, dry_run=dry_run)
                cmd.extend(valid_files)
                cmd.append(f"{self.config['hostname']}:{self.config['remote_dir']}/")
            else:
                cmd = self._build_scp_cmd(compress=compress, recursive=recursive, verbose=verbose)
                cmd.extend(valid_files)
                cmd.append(f"{self.config['hostname']}:{self.config['remote_dir']}")

            if verbose or dry_run:
                print(f"Running: {' '.join(cmd)}")

            start_time = time.time()
            result = subprocess.run(cmd, timeout=300)
            end_time = time.time()
            duration = end_time - start_time

            if result.returncode == 0:
                if dry_run:
                    print("[DRY RUN] Transfer simulation complete!")
                else:
                    print(f"Files pushed successfully! ({len(valid_files)} files in {duration:.2f}s)")
                return True
            else:
                print("Failed to push files.")
                return False
        except subprocess.TimeoutExpired:
            print("File transfer timed out.")
            return False
        except OSError as e:
            print(f"Error pushing files: {e}")
            return False

    def pull_files(self, remote_files, local_dest=".", verbose=False, compress=False, recursive=False, dry_run=False):
        """Pull files from remote device"""
        if not self.config:
            print("No configuration found. Run setup first.")
            return False

        if not remote_files:
            print("No remote files specified to pull.")
            return False

        use_rsync = self.config.get('transfer_method', 'scp') == 'rsync' and self.has_rsync

        if dry_run:
            print(f"[DRY RUN] Would pull {len(remote_files)} file(s) from remote device...")
        else:
            print(f"Pulling {len(remote_files)} file(s) from remote device...")

        try:
            if use_rsync:
                cmd = self._build_rsync_cmd(compress=compress, verbose=verbose, dry_run=dry_run)
                for rf in remote_files:
                    # Handle relative paths
                    if not rf.startswith('/') and not rf.startswith('~'):
                        rf = f"{self.config['remote_dir']}/{rf}"
                    cmd.append(f"{self.config['hostname']}:{rf}")
                cmd.append(local_dest)
            else:
                cmd = self._build_scp_cmd(compress=compress, recursive=recursive, verbose=verbose)
                for rf in remote_files:
                    if not rf.startswith('/') and not rf.startswith('~'):
                        rf = f"{self.config['remote_dir']}/{rf}"
                    cmd.append(f"{self.config['hostname']}:{rf}")
                cmd.append(local_dest)

            if verbose or dry_run:
                print(f"Running: {' '.join(cmd)}")

            start_time = time.time()
            result = subprocess.run(cmd, timeout=300)
            end_time = time.time()
            duration = end_time - start_time

            if result.returncode == 0:
                if dry_run:
                    print("[DRY RUN] Transfer simulation complete!")
                else:
                    print(f"Files pulled successfully! ({len(remote_files)} files in {duration:.2f}s)")
                return True
            else:
                print("Failed to pull files.")
                return False
        except subprocess.TimeoutExpired:
            print("File transfer timed out.")
            return False
        except OSError as e:
            print(f"Error pulling files: {e}")
            return False

    def get_all_non_hidden_files(self, recursive=False):
        """Get all non-hidden files in the current directory"""
        files = []
        current_dir = os.getcwd()

        try:
            if recursive:
                for root, dirs, filenames in os.walk(current_dir):
                    # Skip hidden directories
                    dirs[:] = [d for d in dirs if not d.startswith('.')]
                    for filename in filenames:
                        if not filename.startswith('.'):
                            files.append(os.path.join(root, filename))
            else:
                for item in os.listdir(current_dir):
                    item_path = os.path.join(current_dir, item)
                    # Skip hidden files (starting with .) and directories
                    if not item.startswith('.') and os.path.isfile(item_path):
                        files.append(item)

            if not files:
                print("No non-hidden files found in current directory.")
            else:
                print(f"Found {len(files)} non-hidden files to push.")

            return files
        except OSError as e:
            print(f"Error scanning directory: {e}")
            return []

    def speed_test(self, file_size_mb=10):
        """Test file transfer speed by creating a test file and measuring transfer time"""
        if not self.config:
            print("No configuration found. Run setup first.")
            return False

        print(f"Running speed test with {file_size_mb}MB test file...")

        # Create a temporary test file
        test_file_path = None
        try:
            # Create a temporary file with random data
            fd, test_file_path = tempfile.mkstemp(suffix='.test')

            try:
                # Generate random data (approximately file_size_mb MB)
                chunk_size = 1024 * 1024  # 1MB chunks
                total_bytes = file_size_mb * 1024 * 1024
                bytes_written = 0

                while bytes_written < total_bytes:
                    chunk = os.urandom(min(chunk_size, total_bytes - bytes_written))
                    os.write(fd, chunk)
                    bytes_written += len(chunk)
            finally:
                os.close(fd)

            # Get file size for accurate measurement
            actual_size = os.path.getsize(test_file_path)
            actual_size_mb = actual_size / (1024 * 1024)

            print(f"Created test file: {test_file_path} ({actual_size_mb:.2f} MB)")

            # Use configured transfer method
            use_rsync = self.config.get('transfer_method', 'scp') == 'rsync' and self.has_rsync

            if use_rsync:
                cmd = self._build_rsync_cmd(compress=False, verbose=False)
                cmd.append(test_file_path)
                cmd.append(f"{self.config['hostname']}:{self.config['remote_dir']}/speed_test.tmp")
            else:
                cmd = self._build_scp_cmd()
                cmd.append(test_file_path)
                cmd.append(f"{self.config['hostname']}:{self.config['remote_dir']}/speed_test.tmp")

            print("Starting file transfer speed test...")
            start_time = time.time()

            try:
                # Run without capturing output to allow password prompt and progress bar
                result = subprocess.run(cmd, timeout=300)
                end_time = time.time()

                if result.returncode == 0:
                    transfer_time = end_time - start_time
                    speed_mbps = (actual_size_mb * 8) / transfer_time  # Convert to Mbps
                    speed_mb_per_sec = actual_size_mb / transfer_time

                    print("")
                    print("Speed Test Results:")
                    print("==================")
                    print(f"File size: {actual_size_mb:.2f} MB")
                    print(f"Transfer time: {transfer_time:.2f} seconds")
                    print(f"Transfer speed: {speed_mb_per_sec:.2f} MB/s")
                    print(f"Transfer speed: {speed_mbps:.2f} Mbps")
                    print(f"Method: {'rsync' if use_rsync else 'scp'}")

                    # Clean up remote test file
                    cleanup_cmd = self._build_ssh_base_cmd()
                    cleanup_cmd.append(f"rm -f {self.config['remote_dir']}/speed_test.tmp")

                    # We might need password again here, but for now let's suppress output to keep it clean
                    # If it hangs on password prompt, user will know
                    subprocess.run(cleanup_cmd, capture_output=True, timeout=10)

                    return True
                else:
                    print("Speed test failed.")
                    return False

            except subprocess.TimeoutExpired:
                print("Speed test timed out after 5 minutes.")
                return False
            except OSError as e:
                print(f"Speed test error: {e}")
                return False

        except OSError as e:
            print(f"Error creating test file: {e}")
            return False
        finally:
            # Clean up local test file
            if test_file_path and os.path.exists(test_file_path):
                try:
                    os.unlink(test_file_path)
                except OSError:
                    pass


def main():
    parser = argparse.ArgumentParser(
        description="SSH File Push Tool - Push and pull files to/from remote device",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        usage="sshp [options] [files ...]",
        epilog="""
Examples:
  sshp --setup                    # Setup SSH configuration
  sshp file.txt                   # Push file
  sshp --pull remote.txt          # Pull file from remote
  sshp -r dir/                    # Push/Pull directory recursively
  sshp --test                     # Test connection
"""
    )
    
    # Primary Argument
    parser.add_argument('files', nargs='*', help='Files to push/pull')

    # Configuration Group
    config_group = parser.add_argument_group('Configuration')
    config_group.add_argument('--setup', '-s', action='store_true', help='Setup SSH configuration')
    config_group.add_argument('--global-setup', '-gs', action='store_true', help='Setup global config (~/.sshp_config.json)')
    config_group.add_argument('--local-setup', '-ls', action='store_true', help='Setup local config (./.sshp_config.json)')
    config_group.add_argument('--edit', '-e', action='store_true', help='Edit existing configuration')
    config_group.add_argument('--config', '-c', action='store_true', help='Show current configuration')

    # Actions Group
    action_group = parser.add_argument_group('Actions')
    action_group.add_argument('--pull', '-p', action='store_true', help='Pull files from remote')
    action_group.add_argument('--list', '-l', action='store_true', help='List remote files')
    action_group.add_argument('--test', '-t', action='store_true', help='Test SSH connection')
    action_group.add_argument('--speed-test', '-st', action='store_true', help='Test transfer speed')
    
    # Transfer Options Group
    opt_group = parser.add_argument_group('Transfer Options')
    opt_group.add_argument('--all', '-a', action='store_true', help='Push all non-hidden files')
    opt_group.add_argument('--recursive', '-r', action='store_true', help='Recursive transfer')
    opt_group.add_argument('--compress', '-z', action='store_true', help='Enable compression')
    opt_group.add_argument('--dry-run', '-n', action='store_true', help='Dry run (simulation)')
    opt_group.add_argument('--dest', '-d', default='.', help='Destination for pulled files')
    opt_group.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    opt_group.add_argument('--quiet', '-q', action='store_true', help='Quiet mode (summary only)')
    opt_group.add_argument('--version', action='version', version='sshp 3.5.2')

    args = parser.parse_args()

    tool = SSHpTool()

    if args.quiet:
        tool.config['quiet_mode'] = True

    # Handle different commands
    if args.global_setup:
        tool.setup_global_config()
    elif args.local_setup:
        tool.setup_local_config()
    elif args.setup:
        tool.setup_config()
    elif args.edit:
        tool.edit_config()
    elif args.all:
        # Push all non-hidden files
        files_to_push = tool.get_all_non_hidden_files(recursive=args.recursive)
        if files_to_push:
            tool.push_files(files_to_push, args.verbose, compress=args.compress,
                          recursive=args.recursive, dry_run=args.dry_run)
    elif args.list:
        tool.list_remote_files()
    elif args.test:
        tool.test_connection()
    elif args.speed_test:
        tool.speed_test()
    elif args.config:
        tool.show_config()
    elif args.pull and args.files:
        tool.pull_files(args.files, local_dest=args.dest, verbose=args.verbose,
                       compress=args.compress, recursive=args.recursive, dry_run=args.dry_run)
    elif args.files:
        tool.push_files(args.files, args.verbose, compress=args.compress,
                       recursive=args.recursive, dry_run=args.dry_run)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
EOF
}

# Function to create the self-contained sshp script
create_sshp_script() {
    local install_dir="$HOME/.local/bin"
    local script_path="$install_dir/sshp"

    print_status "Creating self-contained SSHp script..." >&2

    # Create the installation directory
    mkdir -p "$install_dir"

    # Create the self-contained script
    if ! output_sshp_script > "$script_path"; then
        print_error "Failed to create SSHp script"
        return 1
    fi

    # Make the script executable
    if ! chmod +x "$script_path"; then
        print_error "Failed to make SSHp script executable"
        return 1
    fi

    # Verify the script was created successfully
    if [[ ! -f "$script_path" ]] || [[ ! -x "$script_path" ]]; then
        print_error "Failed to create executable script at $script_path"
        return 1
    fi

    print_success "SSHp script created at $script_path" >&2

    echo "$script_path"
}

# Function to setup shell alias
setup_shell_alias() {
    local script_path="$1"

    print_status "Setting up shell alias..." >&2

    # Determine shell configuration file
    local shell_rc=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi

    # Create file if it doesn't exist
    touch "$shell_rc"

    # Remove existing alias if present (cross-platform)
    if grep -q "alias sshp=" "$shell_rc" 2>/dev/null; then
        # Create backup
        cp "$shell_rc" "$shell_rc.bak"
        grep -v "# SSHp Tool alias" "$shell_rc.bak" | grep -v "alias sshp=" > "$shell_rc"
        print_status "Removed existing sshp alias" >&2
    fi

    # Add new alias with proper quoting
    echo "" >> "$shell_rc"
    echo "# SSHp Tool alias" >> "$shell_rc"
    echo "alias sshp=\"$script_path\"" >> "$shell_rc"

    print_success "SSHp alias added to $shell_rc" >&2
}

# Function to remove SSHp tool
remove_sshp_tool() {
    print_status "Removing SSHp tool..."

    local script_path="$HOME/.local/bin/sshp"

    if [[ -f "$script_path" ]]; then
        if rm "$script_path"; then
            print_success "SSHp tool removed from $script_path"
        else
            print_error "Failed to remove SSHp tool"
            return 1
        fi
    else
        print_warning "SSHp tool not found at $script_path"
    fi

    # Remove the ~/.local/bin directory if it's empty
    if [[ -d "$HOME/.local/bin" ]] && [[ -z "$(ls -A "$HOME/.local/bin")" ]]; then
        rmdir "$HOME/.local/bin"
        print_status "Removed empty ~/.local/bin directory"
    fi
}

# Function to remove shell alias
remove_shell_alias() {
    print_status "Removing SSHp command alias..."

    # Determine shell configuration file
    local shell_rc=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi

    if [[ -f "$shell_rc" ]]; then
        # Remove sshp alias lines
        if grep -q "alias sshp=" "$shell_rc"; then
            # Create backup
            local backup_file="$shell_rc.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$shell_rc" "$backup_file"

            # Remove alias lines (cross-platform using grep)
            grep -v "# SSHp Tool alias" "$shell_rc" | grep -v "alias sshp=" > "$shell_rc.tmp"
            mv "$shell_rc.tmp" "$shell_rc"

            print_success "SSHp alias removed from $shell_rc"
            print_status "Backup created: $backup_file"
        else
            print_warning "SSHp alias not found in $shell_rc"
        fi
    else
        print_warning "Shell configuration file not found: $shell_rc"
    fi
}

# Function to remove SSH configuration files
remove_ssh_config_files() {
    if [[ "$KEEP_CONFIG" == "true" ]]; then
        print_status "Keeping SSH configuration files (--keep-config specified)"
        return 0
    fi

    print_status "Removing SSH configuration files..."

    # Remove SSH configuration file
    local ssh_config=".sshp_config.json"
    if [[ -f "$ssh_config" ]]; then
        if rm "$ssh_config"; then
            print_success "SSH configuration file removed: $ssh_config"
        else
            print_warning "Failed to remove SSH configuration file: $ssh_config"
        fi
    else
        print_warning "SSH configuration file not found: $ssh_config"
    fi

    # Remove SSH configuration file from home directory (if it exists there)
    local home_ssh_config="$HOME/.sshp_config.json"
    if [[ -f "$home_ssh_config" ]]; then
        if rm "$home_ssh_config"; then
            print_success "SSH configuration file removed from home: $home_ssh_config"
        else
            print_warning "Failed to remove SSH configuration file from home: $home_ssh_config"
        fi
    fi
}

# Function to check installation status
check_installation_status() {
    print_status "Checking SSHp tool installation status..."

    local script_path="$HOME/.local/bin/sshp"
    local shell_rc=""

    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi

    echo "Installation Status:"
    echo "==================="
    echo "Detected OS: $OS_TYPE"
    echo ""

    # Check if script exists
    if [[ -f "$script_path" ]]; then
        print_success "✓ SSHp script found at: $script_path"
    else
        print_warning "✗ SSHp script not found at: $script_path"
    fi

    # Check if script is executable
    if [[ -x "$script_path" ]]; then
        print_success "✓ SSHp script is executable"
    else
        print_warning "✗ SSHp script is not executable"
    fi

    # Check current version
    local current_version=$(get_current_version)
    if [[ "$current_version" != "not installed" ]]; then
        print_success "✓ Current version: $current_version"

        # Show checksum for verification
        local current_checksum=$(get_script_checksum "$script_path")
        if [[ -n "$current_checksum" ]]; then
            print_status "  Checksum: ${current_checksum:0:16}..."
        fi
    else
        print_warning "✗ Version: $current_version"
    fi

    # Check if alias exists
    if [[ -f "$shell_rc" ]] && grep -q "alias sshp=" "$shell_rc"; then
        print_success "✓ SSHp alias found in: $shell_rc"
    else
        print_status "ℹ SSHp alias not found in: $shell_rc (not required if binary is in PATH)"
    fi

    # Check if command is accessible
    if command -v sshp &> /dev/null; then
        print_success "✓ sshp command is accessible"
    else
        print_warning "✗ sshp command is not accessible"
    fi

    # Check for rsync
    if command -v rsync &> /dev/null; then
        print_success "✓ rsync is available"
    else
        print_status "ℹ rsync not found (scp will be used)"
    fi

    # Check for configuration files
    local config_files=(".sshp_config.json" "$HOME/.sshp_config.json")
    local config_found=false

    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            print_success "✓ SSH configuration found: $config_file"
            config_found=true
        fi
    done

    if [[ "$config_found" == "false" ]]; then
        print_warning "✗ No SSH configuration files found"
    fi
}

# Function to confirm operation
confirm_operation() {
    local operation="$1"

    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    case "$operation" in
        "Install")
            echo "SSHp Tool - Install"
            echo "======================="
            echo "Install to ~/.local/bin/ and add shell alias"
            echo "Detected OS: $OS_TYPE"
            ;;
        "Uninstall")
            echo "SSHp Tool - Uninstall"
            echo "========================="
            echo "Remove tool, alias"
            if [[ "$KEEP_CONFIG" != "true" ]]; then
                echo "Remove configuration files"
            fi
            ;;
        "Update")
            # Get current version for update
            local script_path="$HOME/.local/bin/sshp"
            local current_version="not installed"
            local new_version="3.5.2"

            if [[ -f "$script_path" ]]; then
                current_version=$(grep -o "version='sshp [0-9]\+\.[0-9]\+\.[0-9]\+'" "$script_path" 2>/dev/null | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)
                if [[ -z "$current_version" ]]; then
                    current_version="unknown"
                fi
            fi

            echo "SSHp Tool - Update"
            echo "======================"
            echo "Current: $current_version"
            echo "New:     $new_version"
            echo "Configuration will be preserved"

            # If same version, show additional details
            if [[ "$current_version" == "$new_version" ]] && [[ "$current_version" != "not installed" ]]; then
                echo ""
                echo "Same version detected. Checking for changes..."

                # Get current checksum and file info
                local current_checksum=$(get_script_checksum "$script_path")
                local current_size=$(get_file_size "$script_path")
                local current_date=$(get_file_date "$script_path")

                # Create temporary new script to compare
                local temp_script=$(mktemp)
                output_sshp_script > "$temp_script" 2>/dev/null
                local new_checksum=$(get_script_checksum "$temp_script")
                local new_size=$(get_file_size "$temp_script")
                rm -f "$temp_script"

                echo "Current checksum: ${current_checksum:0:12}..."
                echo "Remote checksum:  ${new_checksum:0:12}..."

                if [[ "$current_size" != "unknown" ]] && [[ "$new_size" != "unknown" ]]; then
                    echo "File sizes: ${current_size}B vs ${new_size}B"
                fi

                if [[ "$current_checksum" != "$new_checksum" ]]; then
                    echo ""
                    echo "Code has changed despite same version."
                    echo "Recommend updating to get latest changes."
                else
                    echo ""
                    echo "No changes detected - already up to date."
                    echo "Update anyway? (y/N): "
                    read -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        print_status "Update cancelled"
                        exit 0
                    fi
                    # If user chose to update anyway, skip the main confirmation
                    return 0
                fi
            fi
            ;;
    esac

    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "$operation cancelled"
        exit 0
    fi
}

# Function to install SSHp tool
install_sshp() {
    print_status "Installing SSHp tool..."

    # Create the self-contained script
    local script_path=$(create_sshp_script)

    # Setup shell alias
    setup_shell_alias "$script_path"

    # Show completion message
    echo ""
    print_success "SSHp tool has been installed successfully!"
    print_status "You can now use 'sshp' command from anywhere"
    print_status "To get started, run: sshp --help"
    print_status "To setup SSH configuration, run: sshp --setup"
    echo ""
    print_status "New features in v3.5.2:"
    echo "  • Improved help message and command organization"
    echo "  • Global config fallback (~/.sshp_config.json)"
    echo "  • Pull files from remote (--pull)"
    echo "  • Recursive directory support (-r)"
    echo "  • Compression option (-z)"
    echo "  • Dry-run mode (-n)"
    echo "  • Rsync support (auto-detected)"
    echo ""
    print_status "To update later, run:"
    print_status "  bash <(curl -s https://raw.githubusercontent.com/abhinav937/sshp/main/sshp-manager.sh) update"
}

# function to uninstall SSHp tool
uninstall_sshp() {
    print_status "Uninstalling SSHp tool..."

    # Remove SSHp tool
    remove_sshp_tool

    # Remove shell alias
    remove_shell_alias

    # Remove SSH configuration files
    remove_ssh_config_files

    # Show uninstallation summary
    echo ""
    print_success "SSHp tool has been uninstalled"
    print_status "The following components were removed:"
    echo "  • SSHp tool executable"
    echo "  • Shell alias"

    if [[ "$KEEP_CONFIG" != "true" ]]; then
        echo "  • SSH configuration files"
    fi

    echo ""
    print_status "If you want to reinstall SSHp tool, run:"
    print_status "  bash <(curl -s https://raw.githubusercontent.com/abhinav937/sshp/main/sshp-manager.sh) install"
    echo ""
    print_status "Note: You may need to restart your terminal for all changes to take effect"
}

# Function to get current version
get_current_version() {
    local script_path="$HOME/.local/bin/sshp"
    if [[ -f "$script_path" ]]; then
        # Extract version from the script
        local version=$(grep -o "version='sshp [0-9]\+\.[0-9]\+\.[0-9]\+'" "$script_path" 2>/dev/null | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)
        if [[ -n "$version" ]]; then
            echo "$version"
        else
            echo "unknown"
        fi
    else
        echo "not installed"
    fi
}

# Function to get script checksum
get_script_checksum() {
    local script_path="$1"
    if [[ -f "$script_path" ]]; then
        # Get SHA256 checksum of the script content (cross-platform)
        if command -v sha256sum &> /dev/null; then
            sha256sum "$script_path" 2>/dev/null | cut -d' ' -f1
        elif command -v shasum &> /dev/null; then
            shasum -a 256 "$script_path" 2>/dev/null | cut -d' ' -f1
        else
            echo ""
        fi
    else
        echo ""
    fi
}

# Function to update SSHp tool
update_sshp() {
    print_status "Updating SSHp tool..."

    # Check if tool is currently installed
    local script_path="$HOME/.local/bin/sshp"
    if [[ ! -f "$script_path" ]]; then
        print_warning "SSHp tool is not installed. Installing instead..."
        install_sshp
        return
    fi

    # For same version updates, checksum comparison is already done in confirm_operation
    local current_version=$(get_current_version)
    local new_version="3.5.2"

    if [[ "$current_version" == "$new_version" ]]; then
        # If we reach here, user chose to update anyway or code changed
        print_status "Updating to latest code..."
    fi

    # Create the updated self-contained script
    local new_script_path=$(create_sshp_script)

    # Show completion message
    echo ""
    print_success "SSHp tool has been updated successfully!"
    print_status "Your existing configuration has been preserved."
    print_status "To verify the update, run: sshp --version"
    echo ""
    print_status "What's new in v3.5.2:"
    echo "  • Improved help message and command organization"
    echo "  • Global config fallback (~/.sshp_config.json)"
    echo "  • Pull files from remote (--pull)"
    echo "  • Recursive directory support (-r)"
    echo "  • Compression option (-z)"
    echo "  • Dry-run mode (-n)"
    echo "  • Rsync support (auto-detected)"
    echo "  • Improved macOS/FreeBSD compatibility"
}

# Parse command line arguments
COMMAND=""
FORCE=false
KEEP_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        install|i)
            COMMAND="install"
            shift
            ;;
        uninstall|u)
            COMMAND="uninstall"
            shift
            ;;
        update|up)
            COMMAND="update"
            shift
            ;;
        status|s)
            COMMAND="status"
            shift
            ;;
        help|h)
            show_help
            exit 0
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --keep-config)
            KEEP_CONFIG=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
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
    *)
        print_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac
