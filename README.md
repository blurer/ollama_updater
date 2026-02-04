# Ollama Updater

A bash script that updates [Ollama](https://ollama.com) while preserving your custom systemd service configuration.

## Why

The official Ollama install script overwrites `/etc/systemd/system/ollama.service` on every run, resetting any custom environment variables, GPU settings, or resource limits you've configured. This script backs up your service file before updating and restores it afterward.

## Usage

```bash
# Update to latest stable release (default)
./update_ollama.sh

# Check available versions and release notes without installing
./update_ollama.sh --check

# Install the latest pre-release
./update_ollama.sh --pre-release
```

### Flags

| Flag | Short | Description |
|------|-------|-------------|
| *(none)* | | Install latest stable release via the official install script |
| `--check` | `-c` | Show current, latest stable, and latest pre-release versions with release notes. Does not install anything. |
| `--pre-release` | `-p` | Fetch the latest pre-release, display release notes, and prompt to confirm before installing. |

## What it does

1. Shows the currently installed Ollama version
2. Backs up `/etc/systemd/system/ollama.service`
3. Installs the new version:
   - **Stable**: runs the official install script from `ollama.com`
   - **Pre-release**: downloads the binary archive directly from GitHub release assets
4. Restores the backed-up service file
5. Reloads systemd and restarts the Ollama service

## Requirements

- Linux (amd64 or arm64)
- `curl`
- `jq` or `python3` (for `--check` and `--pre-release` flag JSON parsing)
- `zstd` (for `--pre-release` installs; pre-release archives use `.tar.zst` format)
- `sudo` access

## License

MIT
