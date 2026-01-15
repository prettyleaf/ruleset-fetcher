#!/bin/bash

VERSION="1.0.1"
GITHUB_REPO="prettyleaf/ruleset-fetcher"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/ruleset-fetcher.sh"

CONFIG_DIR="/opt/ruleset-fetcher"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
URLS_FILE="${CONFIG_DIR}/urls.txt"
LOG_FILE="${CONFIG_DIR}/ruleset-fetcher.log"
SCRIPT_PATH="/usr/local/bin/ruleset-fetcher"
SYMLINK_PATH="/usr/local/bin/rfetcher"

# Colors with terminal detection (stdout or stderr)
if [[ -t 1 || -t 2 ]]; then
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    CYAN=$'\033[36m'
    GRAY=$'\033[37m'
    LIGHT_GRAY=$'\033[90m'
    NC=$'\033[0m'
    BOLD=$'\033[1m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    GRAY=""
    LIGHT_GRAY=""
    NC=""
    BOLD=""
fi

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

setup_symlink() {
    if [[ "$EUID" -ne 0 ]]; then
        return 1
    fi

    # Setup main symlink (ruleset-fetcher)
    if [[ -L "$SCRIPT_PATH" && "$(readlink -f "$SCRIPT_PATH")" == "$(readlink -f "$0")" ]]; then
        : # Already configured
    elif [[ -d "$(dirname "$SCRIPT_PATH")" ]]; then
        rm -f "$SCRIPT_PATH"
        if [[ "$(readlink -f "$0")" != "${SCRIPT_PATH}" ]]; then
            cp "$(readlink -f "$0")" "${SCRIPT_PATH}"
            chmod +x "${SCRIPT_PATH}"
        fi
    fi

    # Setup short alias symlink (rfetcher)
    if [[ -L "$SYMLINK_PATH" && "$(readlink -f "$SYMLINK_PATH")" == "$SCRIPT_PATH" ]]; then
        : # Already configured
    elif [[ -d "$(dirname "$SYMLINK_PATH")" ]]; then
        rm -f "$SYMLINK_PATH"
        if ln -s "$SCRIPT_PATH" "$SYMLINK_PATH" 2>/dev/null; then
            : # Symlink created
        fi
    fi

    return 0
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

# Cron job marker to identify our entries
CRON_MARKER="# ruleset-fetcher-auto-update"

install_cron_job() {
    local interval_hours="$1"
    
    # Remove existing cron job if any
    remove_cron_job 2>/dev/null || true
    
    # Create cron expression based on interval
    local cron_expr
    case "$interval_hours" in
        1)  cron_expr="0 * * * *" ;;           # Every hour
        3)  cron_expr="0 */3 * * *" ;;         # Every 3 hours
        6)  cron_expr="0 */6 * * *" ;;         # Every 6 hours
        12) cron_expr="0 */12 * * *" ;;        # Every 12 hours
        24) cron_expr="0 0 * * *" ;;           # Daily at midnight
        *)  cron_expr="0 */${interval_hours} * * *" ;;  # Custom interval
    esac
    
    # Get existing crontab or start with empty
    local existing_cron
    existing_cron=$(crontab -l 2>/dev/null) || existing_cron=""
    
    # Add new cron job with marker
    local new_cron_line="${cron_expr} ${SCRIPT_PATH} --update >/dev/null 2>&1 ${CRON_MARKER}"
    
    if [[ -z "$existing_cron" ]]; then
        echo "$new_cron_line" | crontab -
    else
        printf '%s\n%s\n' "$existing_cron" "$new_cron_line" | crontab -
    fi
    
    print_success "Cron job installed"
    print_info "Files will be updated every ${interval_hours} hour(s)"
}

remove_cron_job() {
    local existing_cron
    existing_cron=$(crontab -l 2>/dev/null) || existing_cron=""
    
    if [[ -z "$existing_cron" ]]; then
        print_info "No crontab exists"
        return 0
    fi
    
    # Only remove lines with our specific marker
    local new_cron
    new_cron=$(echo "$existing_cron" | grep -v "$CRON_MARKER" || true)
    
    if [[ -z "$new_cron" ]]; then
        crontab -r 2>/dev/null || true
    else
        echo "$new_cron" | crontab -
    fi
    
    print_success "Cron job removed"
}

show_cron_status() {
    local cron_line
    cron_line=$(crontab -l 2>/dev/null | grep "$CRON_MARKER" || true)
    
    if [[ -n "$cron_line" ]]; then
        print_success "Auto-update cron job is ACTIVE"
        echo ""
        # Show without the marker for cleaner display
        echo "  Schedule: ${cron_line% $CRON_MARKER}"
    else
        print_warning "Auto-update cron job is NOT active"
    fi
}

setup_download_directory() {
    echo ""
    print_info "Step 1: Configure Download Directory"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local default_dir="${CONFIG_DIR}"
    echo -e "Download directory for rule-set files."
    echo -e "Default: ${BOLD}${default_dir}${NC}"
    echo ""
    read -p "Enter download directory [press Enter for default]: " input_dir
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
    echo "Press Enter when done."
    echo ""
    
    URLS=()
    
    while true; do
        read -r -p "URL: " url || true
        if [[ -z "$url" ]]; then
            break
        fi
        if [[ "$url" =~ ^https?:// ]]; then
            URLS+=("$url")
            print_success "Added: $(basename "$url")"
        else
            print_warning "Invalid URL format, skipping: $url"
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
    # Respect RF_NO_CLEAR environment variable: if set, skip clearing the terminal before setup.
    if [[ -t 0 && -z "${RF_NO_CLEAR:-}" ]]; then
        clear
    fi
    print_banner
    check_root
    check_dependencies
    create_config_dir
    
    echo ""
    print_info "Starting Setup Wizard..."
    echo ""
    
    # Step 1: Download Directory
    setup_download_directory
    
    # Step 2: URLs
    setup_urls
    
    # Step 3: Review URLs and download
    if [[ ${#URLS[@]} -gt 0 ]]; then
        echo ""
        print_info "Step 3: Review URLs"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "You have added ${#URLS[@]} URL(s):"
        echo ""
        local i=1
        for url in "${URLS[@]}"; do
            echo "  ${i}) $(basename "$url")"
            ((i++))
        done
        echo ""
        
        while true; do
            read -p "Do you want to modify the list? (y/n) [n]: " modify_urls
            modify_urls="${modify_urls:-n}"
            
            if [[ "$modify_urls" =~ ^[Yy]$ ]]; then
                echo ""
                echo "  1) Add more URLs"
                echo "  2) Remove a URL"
                echo "  3) Clear all and re-enter"
                echo "  0) Done editing"
                echo ""
                read -p "Select option: " edit_option
                
                case "$edit_option" in
                    1)
                        echo ""
                        echo "Enter additional URLs (press Enter twice when done):"
                        while true; do
                            read -p "URL: " url
                            if [[ -z "$url" ]]; then
                                break
                            fi
                            if [[ "$url" =~ ^https?:// ]]; then
                                URLS+=("$url")
                                print_success "Added: $(basename "$url")"
                            else
                                print_warning "Invalid URL format, skipping"
                            fi
                        done
                        ;;
                    2)
                        if [[ ${#URLS[@]} -eq 0 ]]; then
                            print_warning "No URLs to remove"
                        else
                            echo ""
                            local j=1
                            for url in "${URLS[@]}"; do
                                echo "  ${j}) $(basename "$url")"
                                ((j++))
                            done
                            echo ""
                            read -p "Enter number to remove: " remove_num
                            if [[ "$remove_num" =~ ^[0-9]+$ ]] && [[ $remove_num -ge 1 ]] && [[ $remove_num -le ${#URLS[@]} ]]; then
                                unset 'URLS[$((remove_num-1))]'
                                URLS=("${URLS[@]}")
                                print_success "URL removed"
                            else
                                print_error "Invalid selection"
                            fi
                        fi
                        ;;
                    3)
                        URLS=()
                        print_info "All URLs cleared. Enter new URLs:"
                        setup_urls
                        ;;
                    0|"")
                        break
                        ;;
                esac
                
                # Show updated list
                if [[ ${#URLS[@]} -gt 0 ]]; then
                    echo ""
                    echo "Current URLs (${#URLS[@]} total):"
                    local k=1
                    for url in "${URLS[@]}"; do
                        echo "  ${k}) $(basename "$url")"
                        ((k++))
                    done
                fi
            else
                break
            fi
        done
        
        # Ask to download now
        echo ""
        read -p "Download files now? (y/n) [y]: " download_now
        download_now="${download_now:-y}"
        if [[ "$download_now" =~ ^[Yy]$ ]]; then
            save_config
            save_urls
            echo ""
            download_all_files
        fi
    fi
    
    # Step 4: Telegram
    echo ""
    read -p "Do you want to configure Telegram notifications now? (y/n) [n]: " setup_tg_now
    setup_tg_now="${setup_tg_now:-n}"
    
    if [[ "$setup_tg_now" =~ ^[Yy]$ ]]; then
        setup_telegram
    else
        TELEGRAM_ENABLED="false"
        TELEGRAM_BOT_TOKEN=""
        TELEGRAM_CHAT_ID=""
        TELEGRAM_THREAD_ID="0"
        print_info "Telegram notifications skipped. You can configure later from the menu."
    fi
    
    # Step 5: Update interval
    setup_update_interval
    
    save_config
    save_urls
    
    if [[ "$(readlink -f "$0")" != "${SCRIPT_PATH}" ]]; then
        cp "$(readlink -f "$0")" "${SCRIPT_PATH}"
        chmod +x "${SCRIPT_PATH}"
        print_success "Script installed to ${SCRIPT_PATH}"
    fi
    
    setup_symlink
    install_cron_job "${UPDATE_INTERVAL}"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "Setup complete!"
    echo ""
    echo "Quick access commands:"
    echo "  ${BOLD}ruleset-fetcher${NC}  - Full command"
    echo "  ${BOLD}rfetcher${NC}         - Short alias"
    echo ""
    echo "Files are saved to: ${DOWNLOAD_DIR}"
    echo "Auto-update every: ${UPDATE_INTERVAL} hour(s)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Press Enter to continue..."
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
    echo "Cron Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    show_cron_status
    
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
        | sed -nE "s/^[[:space:]]*VERSION[[:space:]]*=[[:space:]]*['\"]?([^[:space:]'\"]+)['\"]?.*/\1/p" \
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
    
    # Clean up old backup files (older than 1 day)
    if [[ -f "${SCRIPT_PATH}.backup" ]]; then
        local backup_timestamp
        backup_timestamp=$(stat -c %Y "${SCRIPT_PATH}.backup" 2>/dev/null || stat -f %m "${SCRIPT_PATH}.backup" 2>/dev/null)
        
        if [[ -n "$backup_timestamp" && "$backup_timestamp" =~ ^[0-9]+$ ]]; then
            local backup_age_seconds=$(( $(date +%s) - backup_timestamp ))
            local one_day_seconds=$((24 * 60 * 60))  # 86400 seconds
            
            if [[ $backup_age_seconds -gt $one_day_seconds ]]; then
                rm -f "${SCRIPT_PATH}.backup"
                log_message "INFO" "Removed old backup file (${backup_age_seconds}s old)"
            fi
        fi
    fi
    
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
    
    local download_ref="v${remote_version}"
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
    echo "Usage: ruleset-fetcher [OPTION]  or  rfetcher [OPTION]"
    echo ""
    echo "Running without options opens the interactive menu."
    echo ""
    echo "Options:"
    echo "  --setup, -s       Run interactive setup wizard"
    echo "  --update, -u      Download/update all files now"
    echo "  --status          Show current status and configuration"
    echo "  --add-url         Add a new URL to download"
    echo "  --remove-url      Remove a URL from the list"
    echo "  --list, -l        List all configured URLs"
    echo "  --test-telegram   Send a test Telegram notification"
    echo "  --enable-timer    Enable auto-update cron job"
    echo "  --disable-timer   Disable auto-update cron job"
    echo "  --check-update    Check for script updates"
    echo "  --self-update     Update script to latest version"
    echo "  --version, -v     Show version information"
    echo "  --uninstall       Remove all configuration and cron job"
    echo "  --help, -h        Show this help message"
    echo ""
    echo "Quick access:"
    echo "  ruleset-fetcher   Full command name"
    echo "  rfetcher          Short alias"
    echo ""
    echo "Examples:"
    echo "  sudo ruleset-fetcher         # Open interactive menu"
    echo "  sudo rfetcher --update       # Force update now"
    echo "  sudo rfetcher --add-url      # Add new file URL"
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
        
        remove_cron_job
        
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
                local file_count=$(find "${download_dir}" -type f \( -name "*.mrs" -o -name "*.yaml" -o -name "*.yml" -o -name "*.dat" -o -name "*.txt" \) ! -name "urls.txt" 2>/dev/null | wc -l)
                if [[ $file_count -gt 0 ]]; then
                    echo ""
                    print_info "Found ${file_count} downloaded ruleset file(s) in: ${download_dir}"
                    read -p "Remove downloaded files too? (y/n) [n]: " remove_files
                    
                    if [[ "$remove_files" =~ ^[Yy]$ ]]; then
                        rm -rf "${download_dir}"
                        print_success "Downloaded files removed"
                    else
                        print_info "Downloaded files kept in: ${download_dir}"
                        # Only remove config files if download dir is same as config dir
                        if [[ "${download_dir}" == "${CONFIG_DIR}" ]]; then
                            rm -f "${CONFIG_FILE}" "${URLS_FILE}" "${LOG_FILE}"
                        fi
                    fi
                fi
            else
                print_warning "Downloaded files in ${download_dir} were not removed (system directory)"
            fi
        fi
        
        # Remove config directory if it still exists and is different from download dir
        if [[ -d "${CONFIG_DIR}" ]] && [[ "${CONFIG_DIR}" != "${download_dir}" ]]; then
            rm -rf "${CONFIG_DIR}"
        fi
        
        # Remove symlinks and script
        rm -f "${SYMLINK_PATH}" 2>/dev/null
        rm -f "${SCRIPT_PATH}" 2>/dev/null
        
        echo ""
        print_success "Uninstall complete!"
    else
        print_info "Uninstall cancelled"
    fi
}

main_menu() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}RULESET FETCHER by prettyleaf${NC}"
        echo -e "${LIGHT_GRAY}Version: ${VERSION}${NC}"
        echo ""
        echo "   1. Download/update files now"
        echo "   2. Manage URLs"
        echo "   3. Show current status"
        echo ""
        echo "   4. Configure Telegram notifications"
        echo "   5. Configure auto-update (cron)"
        echo ""
        echo "   6. Check for script updates"
        echo "   7. Update script"
        echo "   8. Uninstall"
        echo ""
        echo "   0. Exit"
        echo ""
        echo -e "   —  Quick access: ${BOLD}${GREEN}ruleset-fetcher${NC} or ${BOLD}${GREEN}rfetcher${NC}"
        echo ""
        
        read -rp "${GREEN}[?]${NC} Select option: " choice
        echo ""
        
        case $choice in
            1)
                download_all_files
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                manage_urls_menu
                ;;
            3)
                show_status
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)
                configure_telegram_menu
                ;;
            5)
                configure_timer_menu
                ;;
            6)
                check_for_updates
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            7)
                self_update
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            8)
                uninstall
                if [[ ! -f "${CONFIG_FILE}" ]]; then
                    exit 0
                fi
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select from the menu."
                read -rp "Press Enter to continue..."
                ;;
        esac
    done
}

manage_urls_menu() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Manage URLs${NC}"
        echo ""
        
        load_urls
        if [[ ${#URLS[@]} -gt 0 ]]; then
            print_info "Current URLs (${#URLS[@]} total):"
            echo ""
            local i=1
            for url in "${URLS[@]}"; do
                echo "   ${i}) $(basename "$url")"
                ((i++))
            done
        else
            print_warning "No URLs configured"
        fi
        
        echo ""
        echo "   1. Add URL"
        echo "   2. Remove URL"
        echo "   3. List URLs (with full paths)"
        echo ""
        echo "   0. Back to main menu"
        echo ""
        
        read -rp "${GREEN}[?]${NC} Select option: " choice
        echo ""
        
        case $choice in
            1)
                add_url
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                remove_url
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)
                list_urls
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            0)
                break
                ;;
            *)
                print_error "Invalid option."
                read -rp "Press Enter to continue..."
                ;;
        esac
    done
}

configure_telegram_menu() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Configure Telegram Notifications${NC}"
        echo ""
        
        if load_config 2>/dev/null; then
            if [[ "${TELEGRAM_ENABLED}" == "true" ]]; then
                print_success "Telegram notifications: ${BOLD}ENABLED${NC}"
                print_info "Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}..."
                print_info "Chat ID: ${TELEGRAM_CHAT_ID}"
                if [[ -n "${TELEGRAM_THREAD_ID}" ]] && [[ "${TELEGRAM_THREAD_ID}" != "0" ]]; then
                    print_info "Thread ID: ${TELEGRAM_THREAD_ID}"
                fi
            else
                print_warning "Telegram notifications: ${BOLD}DISABLED${NC}"
            fi
        else
            print_warning "Configuration not found"
        fi
        
        echo ""
        echo "   1. Configure Telegram settings"
        echo "   2. Test notification"
        echo "   3. Enable notifications"
        echo "   4. Disable notifications"
        echo ""
        echo "   0. Back to main menu"
        echo ""
        
        read -rp "${GREEN}[?]${NC} Select option: " choice
        echo ""
        
        case $choice in
            1)
                setup_telegram
                save_config
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                test_telegram
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)
                TELEGRAM_ENABLED="true"
                save_config
                print_success "Telegram notifications enabled"
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)
                TELEGRAM_ENABLED="false"
                save_config
                print_success "Telegram notifications disabled"
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            0)
                break
                ;;
            *)
                print_error "Invalid option."
                read -rp "Press Enter to continue..."
                ;;
        esac
    done
}

configure_timer_menu() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Configure Auto-Update (Cron)${NC}"
        echo ""
        
        if load_config 2>/dev/null; then
            print_info "Current interval: ${UPDATE_INTERVAL} hour(s)"
        fi
        
        echo ""
        show_cron_status
        
        echo ""
        echo "   1. Change update interval"
        echo "   2. Enable cron job"
        echo "   3. Disable cron job"
        echo ""
        echo "   0. Back to main menu"
        echo ""
        
        read -rp "${GREEN}[?]${NC} Select option: " choice
        echo ""
        
        case $choice in
            1)
                setup_update_interval
                save_config
                install_cron_job "${UPDATE_INTERVAL}"
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                load_config
                install_cron_job "${UPDATE_INTERVAL}"
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)
                remove_cron_job
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            0)
                break
                ;;
            *)
                print_error "Invalid option."
                read -rp "Press Enter to continue..."
                ;;
        esac
    done
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
            install_cron_job "${UPDATE_INTERVAL}"
            ;;
        --disable-timer)
            check_root
            remove_cron_job
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
            check_root
            setup_symlink
            if [[ -f "${CONFIG_FILE}" ]]; then
                load_config
                main_menu
            else
                run_setup
                main_menu
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
