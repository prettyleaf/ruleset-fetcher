#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

VERSION="1.0.1"
GITHUB_REPO="prettyleaf/ruleset-fetcher"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/ruleset-fetcher.sh"

CONFIG_DIR="/opt/ruleset-fetcher"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
URLS_FILE="${CONFIG_DIR}/urls.txt"
LOG_FILE="${CONFIG_DIR}/ruleset-fetcher.log"
SCRIPT_PATH="/usr/local/bin/ruleset-fetcher"

print_banner() {
    echo -e "${CYAN}"
    echo '            _                _      __      _       _               '
    echo ' _ __ _   _| | ___  ___  ___| |_   / _| ___| |_ ___| |__   ___ _ __ '
    echo '| '\''__| | | | |/ _ \/ __|/ _ \ __| | |_ / _ \ __/ __| '\''_ \ / _ \ '\''__|'
    echo '| |  | |_| | |  __/\__ \  __/ |_  |  _|  __/ || (__| | | |  __/ |   '
    echo '|_|   \__,_|_|\___||___/\___|\__| |_|  \___|\__\___|_| |_|\___|_|   '
    echo -e "${NC}"
    echo -e "                                              ${BLUE}v${VERSION}${NC}"
    echo ""
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_dependencies() {
    local deps=("curl" "wget" "jq" "cron")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warning "Missing dependencies: ${missing[*]}"
        print_info "Installing dependencies..."
        apt-get update -qq
        apt-get install -y -qq curl wget jq cron
        print_success "Dependencies installed"
    else
        print_success "All dependencies are installed"
    fi
}

send_telegram_notification() {
    local message="$1"
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        source "${CONFIG_FILE}"
    fi
    
    if [[ -z "${TELEGRAM_BOT_TOKEN}" ]] || [[ -z "${TELEGRAM_CHAT_ID}" ]]; then
        return 0
    fi
    
    local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    local data="chat_id=${TELEGRAM_CHAT_ID}&text=${message}&parse_mode=HTML"
    
    if [[ -n "${TELEGRAM_THREAD_ID}" ]] && [[ "${TELEGRAM_THREAD_ID}" != "0" ]]; then
        data="${data}&message_thread_id=${TELEGRAM_THREAD_ID}"
    fi
    
    local response=$(curl -s -X POST "${api_url}" -d "${data}" 2>/dev/null)
    
    if echo "$response" | jq -e '.ok == true' > /dev/null 2>&1; then
        log_message "INFO" "Telegram notification sent successfully"
        return 0
    else
        log_message "ERROR" "Failed to send Telegram notification: ${response}"
        return 1
    fi
}

test_telegram() {
    local test_message="🔔 <b>Ruleset Fetcher</b>%0A%0A✅ Test notification successful!%0A%0A📅 $(date '+%Y-%m-%d %H:%M:%S')"
    
    if send_telegram_notification "${test_message}"; then
        print_success "Telegram test message sent successfully!"
    else
        print_error "Failed to send Telegram test message"
    fi
}

create_config_dir() {
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        mkdir -p "${CONFIG_DIR}"
        chmod 755 "${CONFIG_DIR}"
        print_success "Created config directory: ${CONFIG_DIR}"
    fi
}

load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        source "${CONFIG_FILE}"
        return 0
    fi
    return 1
}

save_config() {
    cat > "${CONFIG_FILE}" << EOF
# Ruleset Fetcher Configuration
# Generated on $(date '+%Y-%m-%d %H:%M:%S')

# Download directory for rule-set files
DOWNLOAD_DIR="${DOWNLOAD_DIR}"

# Update interval in hours
UPDATE_INTERVAL="${UPDATE_INTERVAL}"

# Telegram Bot Token (from @BotFather)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"

# Telegram Chat ID (user ID, group ID, or channel ID)
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"

# Telegram Thread/Topic ID (optional, for forum groups)
# Set to 0 or leave empty for direct messages
TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID}"

# Enable Telegram notifications (true/false)
TELEGRAM_ENABLED="${TELEGRAM_ENABLED}"
EOF
    chmod 600 "${CONFIG_FILE}"
    print_success "Configuration saved to ${CONFIG_FILE}"
}

save_urls() {
    printf '%s\n' "${URLS[@]}" > "${URLS_FILE}"
    chmod 644 "${URLS_FILE}"
    print_success "URLs saved to ${URLS_FILE}"
}

load_urls() {
    URLS=()
    if [[ -f "${URLS_FILE}" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] && URLS+=("$line")
        done < "${URLS_FILE}"
    fi
}

download_file() {
    local url="$1"
    local dest_dir="$2"
    local filename=$(basename "$url")
    local dest_path="${dest_dir}/${filename}"
    local temp_path="${dest_path}.tmp"

    mkdir -p "$dest_dir"
    
    if curl -fsSL --connect-timeout 30 --max-time 120 -o "${temp_path}" "${url}" 2>/dev/null; then
        mv "${temp_path}" "${dest_path}"
        chmod 644 "${dest_path}"
        echo "${filename}"
        return 0
    else
        rm -f "${temp_path}" 2>/dev/null
        return 1
    fi
}

download_all_files() {
    local silent_mode="${1:-false}"
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        print_error "Configuration not found. Please run setup first."
        return 1
    fi
    
    source "${CONFIG_FILE}"
    load_urls
    
    if [[ ${#URLS[@]} -eq 0 ]]; then
        print_error "No URLs configured. Please add URLs first."
        return 1
    fi
    
    local success_count=0
    local fail_count=0
    local success_files=()
    local failed_files=()
    local start_time=$(date +%s)
    
    [[ "$silent_mode" != "true" ]] && print_info "Starting download of ${#URLS[@]} file(s)..."
    [[ "$silent_mode" != "true" ]] && echo ""
    
    for url in "${URLS[@]}"; do
        local filename=$(basename "$url")
        [[ "$silent_mode" != "true" ]] && echo -n "  Downloading ${filename}... "
        
        if result=$(download_file "$url" "$DOWNLOAD_DIR"); then
            ((success_count++))
            success_files+=("$filename")
            [[ "$silent_mode" != "true" ]] && print_success "OK"
            log_message "INFO" "Downloaded: ${filename}"
        else
            ((fail_count++))
            failed_files+=("$filename")
            [[ "$silent_mode" != "true" ]] && print_error "FAILED"
            log_message "ERROR" "Failed to download: ${filename} from ${url}"
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    [[ "$silent_mode" != "true" ]] && echo ""
    [[ "$silent_mode" != "true" ]] && print_info "Download complete: ${success_count} succeeded, ${fail_count} failed (${duration}s)"
    
    log_message "INFO" "Download batch complete: ${success_count} succeeded, ${fail_count} failed"
    
    if [[ "${TELEGRAM_ENABLED}" == "true" ]]; then
        local status_emoji="✅"
        local status_text="successful"
        
        if [[ $fail_count -gt 0 ]]; then
            if [[ $success_count -eq 0 ]]; then
                status_emoji="❌"
                status_text="failed"
            else
                status_emoji="⚠️"
                status_text="partial"
            fi
        fi
        
        local message="🔄 <b>Ruleset Fetcher Update</b>%0A%0A"
        message+="${status_emoji} Status: ${status_text}%0A"
        message+="📊 Results: ${success_count}/${#URLS[@]} files%0A"
        message+="⏱ Duration: ${duration}s%0A"
        message+="📅 $(date '+%Y-%m-%d %H:%M:%S')%0A"
        
        if [[ ${#success_files[@]} -gt 0 ]]; then
            message+="%0A✅ <b>Downloaded:</b>%0A"
            for f in "${success_files[@]}"; do
                message+="  • ${f}%0A"
            done
        fi
        
        if [[ ${#failed_files[@]} -gt 0 ]]; then
            message+="%0A❌ <b>Failed:</b>%0A"
            for f in "${failed_files[@]}"; do
                message+="  • ${f}%0A"
            done
        fi
        
        send_telegram_notification "${message}"
    fi
    
    return $fail_count
}

install_systemd_service() {
    local interval_hours="$1"
    
    cat > /etc/systemd/system/ruleset-fetcher.service << EOF
[Unit]
Description=Ruleset Fetcher - Download rule-set files for mihomo
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH} --update
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/ruleset-fetcher.timer << EOF
[Unit]
Description=Run Ruleset Fetcher every ${interval_hours} hour(s)

[Timer]
OnBootSec=5min
OnUnitActiveSec=${interval_hours}h
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable ruleset-fetcher.timer
    systemctl start ruleset-fetcher.timer
    
    print_success "Systemd timer installed and started"
    print_info "Files will be updated every ${interval_hours} hour(s)"
}

remove_systemd_service() {
    systemctl stop ruleset-fetcher.timer 2>/dev/null || true
    systemctl disable ruleset-fetcher.timer 2>/dev/null || true
    rm -f /etc/systemd/system/ruleset-fetcher.service
    rm -f /etc/systemd/system/ruleset-fetcher.timer
    systemctl daemon-reload
    print_success "Systemd timer removed"
}

show_timer_status() {
    if systemctl is-active --quiet ruleset-fetcher.timer; then
        print_success "Auto-update timer is ACTIVE"
        echo ""
        systemctl status ruleset-fetcher.timer --no-pager
    else
        print_warning "Auto-update timer is NOT active"
    fi
}

setup_download_directory() {
    echo ""
    print_info "Step 1: Configure Download Directory"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local default_dir="/opt/ruleset-fetcher"
    read -p "Enter download directory [${default_dir}]: " input_dir
    DOWNLOAD_DIR="${input_dir:-$default_dir}"
    
    if [[ ! -d "${DOWNLOAD_DIR}" ]]; then
        mkdir -p "${DOWNLOAD_DIR}"
        chmod 755 "${DOWNLOAD_DIR}"
        print_success "Created directory: ${DOWNLOAD_DIR}"
    else
        print_success "Using existing directory: ${DOWNLOAD_DIR}"
    fi
}

setup_urls() {
    echo ""
    print_info "Step 2: Configure Download URLs"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Enter the URLs of files to download (one per line)."
    echo "Example: https://github.com/MetaCubeX/meta-rules-dat/raw/meta/geo/geosite/discord.mrs"
    echo ""
    echo "Press Enter twice when done."
    echo ""
    
    URLS=()
    local empty_count=0
    
    while true; do
        read -p "URL: " url
        if [[ -z "$url" ]]; then
            ((empty_count++))
            if [[ $empty_count -ge 1 ]]; then
                break
            fi
        else
            empty_count=0
            if [[ "$url" =~ ^https?:// ]]; then
                URLS+=("$url")
                print_success "Added: $(basename "$url")"
            else
                print_warning "Invalid URL format, skipping: $url"
            fi
        fi
    done
    
    if [[ ${#URLS[@]} -eq 0 ]]; then
        print_warning "No URLs added. You can add them later."
    else
        print_success "Added ${#URLS[@]} URL(s)"
    fi
}

setup_update_interval() {
    echo ""
    print_info "Step 3: Configure Auto-Update Interval"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "How often should files be updated?"
    echo "  1) Every 1 hour"
    echo "  2) Every 3 hours"
    echo "  3) Every 6 hours"
    echo "  4) Every 12 hours"
    echo "  5) Every 24 hours (daily)"
    echo "  6) Custom interval"
    echo ""
    
    read -p "Select option [3]: " interval_option
    interval_option="${interval_option:-3}"
    
    case "$interval_option" in
        1) UPDATE_INTERVAL=1 ;;
        2) UPDATE_INTERVAL=3 ;;
        3) UPDATE_INTERVAL=6 ;;
        4) UPDATE_INTERVAL=12 ;;
        5) UPDATE_INTERVAL=24 ;;
        6)
            read -p "Enter custom interval in hours: " custom_interval
            UPDATE_INTERVAL="${custom_interval:-6}"
            ;;
        *) UPDATE_INTERVAL=6 ;;
    esac
    
    print_success "Update interval set to ${UPDATE_INTERVAL} hour(s)"
}

setup_telegram() {
    echo ""
    print_info "Step 4: Configure Telegram Notifications"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "Enable Telegram notifications? (y/n) [y]: " enable_tg
    enable_tg="${enable_tg:-y}"
    
    if [[ "$enable_tg" =~ ^[Yy]$ ]]; then
        TELEGRAM_ENABLED="true"
        echo ""
        echo "To set up Telegram notifications:"
        echo "  1. Create a bot with @BotFather and get the bot token"
        echo "  2. Get your chat ID from @userinfobot or @getidsbot"
        echo "  3. For groups/channels, add the bot and get the group ID"
        echo "  4. For forum groups with topics, get the thread ID"
        echo ""
        
        read -p "Enter Bot Token: " TELEGRAM_BOT_TOKEN
        read -p "Enter Chat ID: " TELEGRAM_CHAT_ID
        
        echo ""
        echo "For forum groups with topics/threads:"
        read -p "Enter Thread ID (press Enter for direct messages): " TELEGRAM_THREAD_ID
        TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-0}"
        
        if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
            echo ""
            read -p "Send test notification? (y/n) [y]: " send_test
            send_test="${send_test:-y}"
            if [[ "$send_test" =~ ^[Yy]$ ]]; then
                save_config
                test_telegram
            fi
        fi
    else
        TELEGRAM_ENABLED="false"
        TELEGRAM_BOT_TOKEN=""
        TELEGRAM_CHAT_ID=""
        TELEGRAM_THREAD_ID="0"
        print_info "Telegram notifications disabled"
    fi
}

run_setup() {
    print_banner
    check_root
    check_dependencies
    create_config_dir
    
    echo ""
    print_info "Starting interactive setup..."
    
    setup_download_directory
    setup_urls
    setup_update_interval
    setup_telegram
    
    save_config
    save_urls
    
    if [[ "$(readlink -f "$0")" != "${SCRIPT_PATH}" ]]; then
        cp "$(readlink -f "$0")" "${SCRIPT_PATH}"
        chmod +x "${SCRIPT_PATH}"
        print_success "Script installed to ${SCRIPT_PATH}"
    fi
    
    install_systemd_service "${UPDATE_INTERVAL}"
    
    echo ""
    read -p "Download files now? (y/n) [y]: " download_now
    download_now="${download_now:-y}"
    if [[ "$download_now" =~ ^[Yy]$ ]]; then
        echo ""
        download_all_files
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "Setup complete!"
    echo ""
    echo "Useful commands:"
    echo "  ${SCRIPT_PATH} --status    Show current status"
    echo "  ${SCRIPT_PATH} --update    Download files now"
    echo "  ${SCRIPT_PATH} --add-url   Add new URL"
    echo "  ${SCRIPT_PATH} --list      List configured URLs"
    echo "  ${SCRIPT_PATH} --help      Show all commands"
    echo ""
    echo "Files are saved to: ${DOWNLOAD_DIR}"
    echo "Auto-update every: ${UPDATE_INTERVAL} hour(s)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${CYAN}Created by prettyleaf${NC}"
    echo -e "GitHub: ${BLUE}https://github.com/prettyleaf/ruleset-fetcher${NC}"
    echo -e "Donate: ${GREEN}https://github.com/sponsors/prettyleaf${NC}"
    echo ""
    echo "Thank you for using Ruleset Fetcher! ❤️"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

add_url() {
    load_urls
    
    echo ""
    read -p "Enter URL to add: " new_url
    
    if [[ -z "$new_url" ]]; then
        print_error "No URL provided"
        return 1
    fi
    
    if [[ ! "$new_url" =~ ^https?:// ]]; then
        print_error "Invalid URL format"
        return 1
    fi
    
    for url in "${URLS[@]}"; do
        if [[ "$url" == "$new_url" ]]; then
            print_warning "URL already exists"
            return 1
        fi
    done
    
    URLS+=("$new_url")
    save_urls
    print_success "Added: $(basename "$new_url")"
}

remove_url() {
    load_urls
    
    if [[ ${#URLS[@]} -eq 0 ]]; then
        print_error "No URLs configured"
        return 1
    fi
    
    echo ""
    echo "Current URLs:"
    local i=1
    for url in "${URLS[@]}"; do
        echo "  ${i}) $(basename "$url")"
        ((i++))
    done
    
    echo ""
    read -p "Enter number to remove (or 'all' to remove all): " selection
    
    if [[ "$selection" == "all" ]]; then
        URLS=()
        save_urls
        print_success "All URLs removed"
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#URLS[@]} ]]; then
        local removed="${URLS[$((selection-1))]}"
        unset 'URLS[$((selection-1))]'
        URLS=("${URLS[@]}")
        save_urls
        print_success "Removed: $(basename "$removed")"
    else
        print_error "Invalid selection"
        return 1
    fi
}

list_urls() {
    load_urls
    
    if [[ ${#URLS[@]} -eq 0 ]]; then
        print_warning "No URLs configured"
        return 0
    fi
    
    echo ""
    print_info "Configured URLs (${#URLS[@]} total):"
    echo ""
    local i=1
    for url in "${URLS[@]}"; do
        echo "  ${i}) $(basename "$url")"
        echo "     ${url}"
        ((i++))
    done
    echo ""
}

show_status() {
    print_banner
    
    echo "Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if load_config; then
        echo "  Download Directory: ${DOWNLOAD_DIR}"
        echo "  Update Interval:    ${UPDATE_INTERVAL} hour(s)"
        echo "  Telegram Enabled:   ${TELEGRAM_ENABLED}"
        
        load_urls
        echo "  Configured URLs:    ${#URLS[@]}"
        
        # Show files in directory (exclude config files)
        if [[ -d "${DOWNLOAD_DIR}" ]]; then
            local file_count=$(find "${DOWNLOAD_DIR}" -maxdepth 1 -type f \( -name "*.mrs" -o -name "*.yaml" -o -name "*.yml" -o -name "*.dat" \) 2>/dev/null | wc -l)
            echo "  Downloaded Files:   ${file_count}"
        fi
    else
        print_warning "Not configured. Run with --setup to configure."
    fi
    
    echo ""
    echo "Timer Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    show_timer_status
    
    echo ""
    echo "Recent Logs"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ -f "${LOG_FILE}" ]]; then
        tail -10 "${LOG_FILE}"
    else
        echo "  No logs yet"
    fi
}

get_remote_version() {
    local remote_script
    remote_script=$(curl -fsSL --connect-timeout 10 --max-time 30 "${GITHUB_RAW_URL}" 2>/dev/null) || return 1
    
    # Extract VERSION= line robustly, allowing spaces and single/double quotes.
    # Examples handled:
    #   VERSION="1.2.3"
    #   VERSION = '1.2.3'
    #   VERSION=1.2.3
    local version
    version=$(printf '%s\n' "$remote_script" \
        | sed -nE "s/^[[:space:]]*VERSION[[:space:]]*=[[:space:]]*['\"]?([^'\"[:space:]]+)['\"]?.*/\1/p" \
        | head -n1)

    # Validate that a version was found
    if [[ -z "$version" ]]; then
        print_error "Failed to parse remote version information from ${GITHUB_RAW_URL}"
        return 1
    fi

    # Validate version format (optionally leading 'v', then numeric dot-separated parts)
    if ! [[ "$version" =~ ^v?[0-9]+(\.[0-9]+)*$ ]]; then
        print_error "Invalid version format in remote script: '$version'"
        return 1
    fi
    
    echo "${version#v}"
}

compare_versions() {
    local v1="${1#v}"
    local v2="${2#v}"

    if [[ "$v1" == "$v2" ]]; then
        return 0
    fi
    
    local IFS_SAVE="$IFS"
    IFS='.'
    local v1_parts=()
    local v2_parts=()
    read -ra v1_parts <<< "$v1"
    read -ra v2_parts <<< "$v2"
    IFS="$IFS_SAVE"
    
    local i
    for ((i=0; i<${#v1_parts[@]} || i<${#v2_parts[@]}; i++)); do
        local p1=${v1_parts[i]:-0}
        local p2=${v2_parts[i]:-0}
        
        if ((p1 > p2)); then
            return 1
        elif ((p1 < p2)); then
            return 2
        fi
    done
    
    return 0
}

check_for_updates() {
    echo ""
    print_info "Checking for updates..."
    
    local remote_version
    remote_version=$(get_remote_version)
    
    if [[ -z "$remote_version" ]]; then
        print_error "Failed to check for updates. Check your internet connection."
        return 1
    fi
    
    echo "  Current version: ${VERSION}"
    echo "  Latest version:  ${remote_version}"
    echo ""
    
    compare_versions "$VERSION" "$remote_version"
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        print_success "You are running the latest version!"
    elif [[ $result -eq 2 ]]; then
        print_warning "A new version is available: v${remote_version}"
        echo ""
        echo "  Run 'sudo ruleset-fetcher --self-update' to update"
        echo "  Or download from: https://github.com/${GITHUB_REPO}"
    else
        print_info "You are running a newer version than the released one."
    fi
}

self_update() {
    echo ""
    print_info "Checking for updates..."
    
    local remote_version
    remote_version=$(get_remote_version)
    
    if [[ -z "$remote_version" ]]; then
        print_error "Failed to check for updates. Check your internet connection."
        return 1
    fi
    
    compare_versions "$VERSION" "$remote_version"
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        print_success "You are already running the latest version (v${VERSION})"
        return 0
    elif [[ $result -eq 1 ]]; then
        print_info "You are running a newer version (v${VERSION}) than released (v${remote_version})"
        read -p "Downgrade to released version? (y/n) [n]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Update cancelled"
            return 0
        fi
    else
        echo "  Current version: ${VERSION}"
        echo "  Latest version:  ${remote_version}"
        echo ""
        read -p "Update to v${remote_version}? (y/n) [y]: " confirm
        confirm="${confirm:-y}"
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Update cancelled"
            return 0
        fi
    fi
    
    print_info "Downloading update..."
    
    local temp_file
    temp_file="$(mktemp -t ruleset-fetcher-update.XXXXXX)" || {
        print_error "Failed to create temporary file for update"
        return 1
    }
    
    local download_ref="${remote_version}"
    local download_url="https://raw.githubusercontent.com/${GITHUB_REPO}/${download_ref}/ruleset-fetcher.sh"
    
    if ! curl -fsSL --connect-timeout 30 --max-time 120 -o "${temp_file}" "${download_url}" 2>/dev/null; then
        print_error "Failed to download update"
        rm -f "${temp_file}"
        return 1
    fi
    
    if ! head -1 "${temp_file}" | grep -q '^#!/bin/bash'; then
        print_error "Downloaded file is not a valid script"
        rm -f "${temp_file}"
        return 1
    fi
    
    local had_backup=false
    if [[ -f "${SCRIPT_PATH}" ]]; then
        if [[ ! -r "${SCRIPT_PATH}" ]]; then
            print_error "Current script is not readable; aborting update to avoid data loss."
            rm -f "${temp_file}"
            return 1
        fi
        if ! cp "${SCRIPT_PATH}" "${SCRIPT_PATH}.backup"; then
            print_error "Failed to create backup; aborting update to avoid data loss."
            rm -f "${temp_file}"
            return 1
        fi
        had_backup=true
    fi
    
    if ! mv "${temp_file}" "${SCRIPT_PATH}"; then
        print_error "Failed to install update (move operation failed)"
        if [[ "${had_backup}" == true ]]; then
            if mv "${SCRIPT_PATH}.backup" "${SCRIPT_PATH}"; then
                print_info "Restored previous version from backup."
            else
                print_error "Failed to restore previous version from backup at ${SCRIPT_PATH}.backup"
            fi
        fi
        rm -f "${temp_file}"
        return 1
    fi
    
    if ! chmod +x "${SCRIPT_PATH}"; then
        print_error "Failed to make updated script executable (chmod failed)"
        if [[ "${had_backup}" == true ]]; then
            if mv "${SCRIPT_PATH}.backup" "${SCRIPT_PATH}"; then
                print_info "Restored previous version from backup."
            else
                print_error "Failed to restore previous version from backup at ${SCRIPT_PATH}.backup"
            fi
        fi
        return 1
    fi
    
    print_success "Updated successfully to v${remote_version}!"
    echo ""
    if [[ -f "${SCRIPT_PATH}.backup" ]]; then
        print_info "Backup saved to: ${SCRIPT_PATH}.backup"
    fi
    log_message "INFO" "Updated from v${VERSION} to v${remote_version}"
}

show_version() {
    echo "ruleset-fetcher v${VERSION}"
    echo "https://github.com/${GITHUB_REPO}"
}

show_help() {
    print_banner
    echo "Usage: $(basename "$0") [OPTION]"
    echo ""
    echo "Options:"
    echo "  --setup, -s       Run interactive setup wizard"
    echo "  --update, -u      Download/update all files now"
    echo "  --status          Show current status and configuration"
    echo "  --add-url         Add a new URL to download"
    echo "  --remove-url      Remove a URL from the list"
    echo "  --list, -l        List all configured URLs"
    echo "  --test-telegram   Send a test Telegram notification"
    echo "  --enable-timer    Enable auto-update timer"
    echo "  --disable-timer   Disable auto-update timer"
    echo "  --check-update    Check for script updates"
    echo "  --self-update     Update script to latest version"
    echo "  --version, -v     Show version information"
    echo "  --uninstall       Remove all configuration and timers"
    echo "  --help, -h        Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $(basename "$0") --setup       # Initial setup"
    echo "  sudo $(basename "$0") --update      # Force update now"
    echo "  sudo $(basename "$0") --add-url     # Add new file URL"
    echo "  sudo $(basename "$0") --self-update # Update script"
    echo ""
    echo "Configuration files:"
    echo "  ${CONFIG_FILE}"
    echo "  ${URLS_FILE}"
    echo ""
    echo "Log file:"
    echo "  ${LOG_FILE}"
    echo ""
}

uninstall() {
    echo ""
    print_warning "This will remove all configuration and stop auto-updates."
    read -p "Are you sure? (y/n) [n]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local download_dir=""
        if [[ -f "${CONFIG_FILE}" ]]; then
            source "${CONFIG_FILE}"
            download_dir="${DOWNLOAD_DIR}"
        fi
        
        remove_systemd_service
        
        if [[ -n "${download_dir}" ]] && [[ -d "${download_dir}" ]]; then
            local safe_to_delete=true
            local unsafe_dirs=("/" "/etc" "/usr" "/var" "/home" "/root" "/bin" "/sbin" "/lib" "/opt")
            
            for unsafe_dir in "${unsafe_dirs[@]}"; do
                if [[ "${download_dir}" == "${unsafe_dir}" ]] || [[ "${download_dir}" == "${unsafe_dir}/" ]]; then
                    safe_to_delete=false
                    break
                fi
            done
            
            if [[ "${safe_to_delete}" == true ]]; then
                local file_count=$(find "${download_dir}" -type f \( -name "*.mrs" -o -name "*.yaml" -o -name "*.yml" -o -name "*.dat" -o -name "*.txt" ! -name "urls.txt" \) 2>/dev/null | wc -l)
                if [[ $file_count -gt 0 ]]; then
                    echo ""
                    print_info "Found ${file_count} downloaded ruleset file(s) in: ${download_dir}"
                    read -p "Remove downloaded files too? (y/n) [n]: " remove_files
                    
                    if [[ "$remove_files" =~ ^[Yy]$ ]]; then
                        if [[ "${download_dir}" != "${CONFIG_DIR}" ]]; then
                            rm -rf "${download_dir}"
                            print_success "Downloaded files removed"
                        fi
                    else
                        if [[ "${download_dir}" == "${CONFIG_DIR}" ]]; then
                            rm -f "${CONFIG_FILE}" "${URLS_FILE}" "${LOG_FILE}"
                            print_success "Configuration removed"
                            print_info "Downloaded files kept in: ${download_dir}"
                            rm -f "${SCRIPT_PATH}"
                            echo ""
                            print_success "Uninstall complete!"
                            return
                        else
                            print_info "Downloaded files kept in: ${download_dir}"
                        fi
                    fi
                fi
            else
                print_warning "Downloaded files in ${download_dir} were not removed (system directory)"
            fi
        fi
        
        rm -rf "${CONFIG_DIR}"
        rm -f "${SCRIPT_PATH}"
        
        echo ""
        print_success "Uninstall complete!"
    else
        print_info "Uninstall cancelled"
    fi
}

main() {
    case "${1:-}" in
        --setup|-s)
            run_setup
            ;;
        --update|-u)
            check_root
            download_all_files
            ;;
        --status)
            show_status
            ;;
        --add-url)
            check_root
            add_url
            ;;
        --remove-url)
            check_root
            remove_url
            ;;
        --list|-l)
            list_urls
            ;;
        --test-telegram)
            check_root
            load_config
            test_telegram
            ;;
        --enable-timer)
            check_root
            load_config
            install_systemd_service "${UPDATE_INTERVAL}"
            ;;
        --disable-timer)
            check_root
            remove_systemd_service
            ;;
        --uninstall)
            check_root
            uninstall
            ;;
        --check-update)
            check_for_updates
            ;;
        --self-update)
            check_root
            self_update
            ;;
        --version|-v)
            show_version
            ;;
        --help|-h)
            show_help
            ;;
        "")
            if [[ -f "${CONFIG_FILE}" ]]; then
                show_help
            else
                echo ""
                print_info "First time setup detected."
                read -p "Run setup wizard? (y/n) [y]: " run_setup_prompt
                run_setup_prompt="${run_setup_prompt:-y}"
                if [[ "$run_setup_prompt" =~ ^[Yy]$ ]]; then
                    run_setup
                else
                    show_help
                fi
            fi
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help to see available options"
            exit 1
            ;;
    esac
}

main "$@"
