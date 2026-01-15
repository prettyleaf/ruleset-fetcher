# ruleset-fetcher

An interactive script that fetches rule-set files for [mihomo](https://github.com/MetaCubeX/mihomo).

## Quick Start

```bash
wget https://raw.githubusercontent.com/prettyleaf/ruleset-fetcher/main/ruleset-fetcher.sh
chmod +x ruleset-fetcher.sh
sudo ./ruleset-fetcher.sh --setup
```

```bash
curl -fsSL https://raw.githubusercontent.com/prettyleaf/ruleset-fetcher/main/ruleset-fetcher.sh -o /tmp/ruleset-fetcher.sh && sudo bash /tmp/ruleset-fetcher.sh --setup
```

## Usage

```bash
sudo ruleset-fetcher --setup
```

- **Download Directory** - Where to save rule-set files (default: `/opt/ruleset-fetcher`)
- **URLs** - Add multiple URLs to download
- **Update Interval** - How often to check for updates
- **Telegram Notifications** - Optional alerts for updates

| Command | Description |
|---------|-------------|
| `--setup`, `-s` | Run interactive setup wizard |
| `--update`, `-u` | Download/update all files now |
| `--status` | Show current status and configuration |
| `--add-url` | Add a new URL to download |
| `--remove-url` | Remove a URL from the list |
| `--list`, `-l` | List all configured URLs |
| `--test-telegram` | Send a test Telegram notification |
| `--enable-timer` | Enable auto-update timer |
| `--disable-timer` | Disable auto-update timer |
| `--check-update` | Check for script updates |
| `--self-update` | Update script to latest version |
| `--version`, `-v` | Show version information |
| `--uninstall` | Remove all configuration and timers |
| `--help`, `-h` | Show help message |

### Examples

```bash
sudo ruleset-fetcher --update

sudo ruleset-fetcher --add-url

sudo ruleset-fetcher --status

ruleset-fetcher --list
```

## Nginx Configuration (by Copilot)

To serve the downloaded files as a GitHub mirror, add this to your Nginx configuration:

```nginx
server {
    listen 80;
    server_name your-mirror-domain.com;

    location /rulesets/ {
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

## Usage in Mihomo Config

Replace GitHub URLs with your mirror:

```yaml
# orig
rule-providers:
  discord:
    type: http
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/meta/geo/geosite/discord.mrs"
    path: ./ruleset/discord.mrs
    behavior: domain
    format: mrs

# with this script
rule-providers:
  discord:
    type: http
    url: "https://your-mirror-domain.com/rulesets/discord.mrs"
    path: ./ruleset/discord.mrs
    behavior: domain
    format: mrs
```

## Files created by script

| File | Description |
|------|-------------|
| `/opt/ruleset-fetcher/config.conf` | Main configuration file |
| `/opt/ruleset-fetcher/urls.txt` | List of URLs to download |
| `/opt/ruleset-fetcher/ruleset-fetcher.log` | Log file |
| `/etc/systemd/system/ruleset-fetcher.timer` | Systemd timer unit |
| `/etc/systemd/system/ruleset-fetcher.service` | Systemd service unit |


## Check Service Status

```bash
systemctl status ruleset-fetcher.timer

systemctl status ruleset-fetcher.service

journalctl -u ruleset-fetcher.service -f
```

## Manual Log Check

```bash
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