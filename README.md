# ruleset-fetcher

An interactive script that fetches rule-set files for [mihomo](https://github.com/MetaCubeX/mihomo).

![ruleset-fetcher](.github/assets/wizard.png)

## Quick Start

```bash
wget https://raw.githubusercontent.com/prettyleaf/ruleset-fetcher/main/ruleset-fetcher.sh
chmod +x ruleset-fetcher.sh
sudo ./ruleset-fetcher.sh
```

```bash
curl -fsSL https://raw.githubusercontent.com/prettyleaf/ruleset-fetcher/main/ruleset-fetcher.sh -o /tmp/ruleset-fetcher.sh && sudo bash /tmp/ruleset-fetcher.sh
```

After installation, you can use either command from anywhere:
```bash
ruleset-fetcher
rfetcher
```

## Usage

Running without arguments opens the interactive menu:

```bash
ruleset-fetcher
```

### Setup Wizard

The setup wizard guides you through:

1. **Download Directory** - Where to save rule-set files (default: `/opt/ruleset-fetcher`)
2. **URLs** - Add multiple URLs to download
3. **Review & Download** - Confirm URLs and optionally download immediately
4. **Telegram Notifications** - Optional alerts for updates
5. **Update Interval** - How often to auto-update (via cron)

### Commands

| Command | Description |
|---------|-------------|
| `--setup`, `-s` | Run interactive setup wizard |
| `--update`, `-u` | Download/update all files now |
| `--status` | Show current status and configuration |
| `--add-url` | Add a new URL to download |
| `--remove-url` | Remove a URL from the list |
| `--list`, `-l` | List all configured URLs |
| `--test-telegram` | Send a test Telegram notification |
| `--enable-timer` | Enable auto-update cron job |
| `--disable-timer` | Disable auto-update cron job |
| `--check-update` | Check for script updates |
| `--self-update` | Update script to latest version |
| `--version`, `-v` | Show version information |
| `--uninstall` | Remove all configuration and cron job |
| `--help`, `-h` | Show help message |


## Nginx Configuration

To serve the downloaded files as a GitHub mirror, add this to your Nginx configuration:

```nginx
server {
    listen 443;
    server_name your-mirror-domain.com;

    location /rule-sets/ {
        alias /opt/ruleset-fetcher/;
        autoindex on;
        
        # CORS headers for mihomo
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods 'GET, OPTIONS';
        
        # Cache control
        expires 1h;
        add_header Cache-Control "public, max-age=3600";
    }
}
```

## Files

| File | Description |
|------|-------------|
| `/usr/local/bin/ruleset-fetcher` | Main script |
| `/usr/local/bin/rfetcher` | Short alias (symlink) |
| `/opt/ruleset-fetcher/config.conf` | Configuration file |
| `/opt/ruleset-fetcher/urls.txt` | List of URLs to download |
| `/opt/ruleset-fetcher/ruleset-fetcher.log` | Log file |

Auto-updates are managed via cron job (viewable with `crontab -l`).

## Check Status

```bash
# Show full status
sudo ruleset-fetcher --status

# Check cron job
crontab -l | grep ruleset-fetcher

# Watch logs
tail -f /opt/ruleset-fetcher/ruleset-fetcher.log
```

## Reset Configuration

```bash
sudo ruleset-fetcher --uninstall
sudo ruleset-fetcher --setup
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

PR welcome.

## Donations

- **Tribute**: https://t.me/tribute/app?startapp=dsRK