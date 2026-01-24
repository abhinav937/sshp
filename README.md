# SSH Push Tool

A simple, cross-platform tool for pushing and pulling files to/from remote devices via SSH.

## Features

- Self-contained Python script
- Works on Linux, macOS, FreeBSD, and Windows (WSL)
- One-line installation
- Interactive setup
- Project-specific SSH settings
- No external dependencies
- **Push and pull** file operations
- **Recursive directory** support
- **Rsync support** (auto-detected) for faster incremental transfers
- **Compression option** for slow connections
- **Dry-run mode** to preview transfers
- Speed testing
- Automatic SSH key setup

## Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/abhinav937/ssh-push/main/ssh-push-manager.sh) install
```

## Update

```bash
bash <(curl -s https://raw.githubusercontent.com/abhinav937/ssh-push/main/ssh-push-manager.sh) update
```

## Uninstall

```bash
bash <(curl -s https://raw.githubusercontent.com/abhinav937/ssh-push/main/ssh-push-manager.sh) uninstall
```

## Quick Start

1. **Setup configuration:**
   ```bash
   ssh-push --setup
   ```

2. **Test connection:**
   ```bash
   ssh-push --test
   ```

3. **Push files:**
   ```bash
   ssh-push file1.v file2.v
   ssh-push --all  # Push all files
   ```

4. **Pull files:**
   ```bash
   ssh-push --pull remote_file.txt
   ssh-push --pull -r logs/  # Pull directory
   ```

## Usage Examples

```bash
# Setup SSH configuration
ssh-push --setup

# Edit configuration
ssh-push --edit

# Push files
ssh-push file1.v file2.v

# Push all files
ssh-push --all

# Push directory recursively
ssh-push -r mydir/

# Push with compression (good for slow connections)
ssh-push -z largefile.bin

# Preview what would be transferred (dry-run)
ssh-push --dry-run file.txt

# Pull files from remote
ssh-push --pull remote_file.txt

# Pull to specific directory
ssh-push --pull -d ./downloads/ remote_file.txt

# Pull directory recursively
ssh-push --pull -r logs/

# List remote files
ssh-push --list

# Test connection
ssh-push --test

# Test speed
ssh-push --speed-test

# Show configuration
ssh-push --config

# Verbose output
ssh-push --verbose file.txt
```

## Command Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--setup` | `-s` | Setup SSH configuration |
| `--edit` | `-e` | Edit existing configuration |
| `--all` | `-a` | Push all non-hidden files |
| `--pull` | `-p` | Pull files from remote |
| `--recursive` | `-r` | Recursive transfer for directories |
| `--compress` | `-z` | Enable compression |
| `--dry-run` | `-n` | Preview without transferring |
| `--dest` | `-d` | Local destination for pulls |
| `--list` | `-l` | List remote files |
| `--test` | `-t` | Test SSH connection |
| `--speed-test` | `-st` | Test transfer speed |
| `--config` | `-c` | Show configuration |
| `--verbose` | `-v` | Verbose output |
| `--version` | | Show version |

## Configuration

The tool stores configuration in `.ssh_push_config.json`:

```json
{
  "hostname": "pi@192.168.1.100",
  "port": 22,
  "remote_dir": "~",
  "transfer_method": "rsync",
  "auth_method": "key",
  "key_path": "~/.ssh/id_rsa"
}
```

### Configuration Options

- **hostname**: Remote host in `user@host` or `host` format
- **port**: SSH port (default: 22)
- **remote_dir**: Default remote directory (default: ~)
- **transfer_method**: `scp` or `rsync` (rsync preferred if available)
- **auth_method**: `key` or `password`
- **key_path**: Path to SSH private key

## Transfer Methods

### SCP (Default fallback)
- Works everywhere SSH works
- Simple and reliable
- Good for single file transfers

### Rsync (Recommended)
- Faster for incremental transfers
- Shows progress during transfer
- Only transfers changed portions of files
- Auto-detected during setup

## SSH Key Setup

### Automatic Setup
The tool can automatically set up SSH keys during configuration:

```bash
ssh-push --setup
```

When you choose key authentication, it will:
1. Check for existing SSH keys
2. Generate new key if needed
3. Copy key to remote machine
4. Set up passwordless authentication

### Manual Setup
```bash
ssh-keygen -t rsa -b 4096
ssh-copy-id pi@192.168.1.100
```

## Troubleshooting

### SSH Connection Issues
```bash
# Check SSH service
sudo systemctl status ssh

# Test basic connection
ssh pi@192.168.1.100
```

### Permission Issues
```bash
# Fix SSH key permissions
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
```

### Installation Issues
```bash
# Check installation
bash <(curl -s https://raw.githubusercontent.com/abhinav937/ssh-push/main/ssh-push-manager.sh) status

# Reinstall if needed
bash <(curl -s https://raw.githubusercontent.com/abhinav937/ssh-push/main/ssh-push-manager.sh) install
```

### macOS Specific
- Rsync is pre-installed on macOS
- Uses `shasum` instead of `sha256sum` for checksums
- All `sed` and `stat` commands are cross-platform compatible

## Version History

### Version 3.4.0
- Added `--pull` command to retrieve files from remote
- Added recursive directory support (`-r`)
- Added compression option (`-z`)
- Added dry-run mode (`-n`)
- Added rsync support (auto-detected)
- Fixed macOS/FreeBSD compatibility (`sed -i`, `stat` commands)
- Fixed `sha256sum` for macOS (uses `shasum -a 256`)
- Improved input validation for hostname, port, and paths
- Changed default remote directory from `~/fpga_work` to `~`
- Removed redundant imports in Python code
- Fixed bare except clauses
- Improved temp file cleanup

### Version 3.3.7
- Fixed checksum comparison for same-version updates
- Corrected script content output for accurate file comparison
- Improved update detection reliability

### Version 3.3.4
- Enhanced same-version update detection with checksum comparison
- Shows detailed file comparison before update confirmation

### Version 3.3.3
- Fixed redundant "Generating" messages during SSH key setup
- Cleaner user feedback during key generation process

### Version 3.3.2
- Fixed SSH key generation to handle existing keys properly
- Improved text messages and user feedback
- Streamlined SSH key setup process

### Version 3.3.1
- Fixed SSH key copying to allow password input
- Improved interactive SSH key setup process

### Version 3.3.0
- Automatic SSH key setup
- Passwordless authentication
- Smart key management

### Version 3.2.0
- Speed testing feature
- File transfer performance measurement

### Version 3.1.0
- Bulk file operations
- Enhanced error handling

## License

MIT License
