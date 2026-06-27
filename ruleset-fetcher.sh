#!/bin/bash

VERSION="26.2.2"
GITHUB_REPO="prettyleaf/ruleset-fetcher"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/ruleset-fetcher.sh"

CONFIG_DIR="/opt/ruleset-fetcher"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
URLS_FILE="${CONFIG_DIR}/urls.txt"
LOG_FILE="${CONFIG_DIR}/ruleset-fetcher.log"
SCRIPT_PATH="/usr/local/bin/ruleset-fetcher"
SYMLINK_PATH="/usr/local/bin/rfetcher"

DOWNLOAD_DIR=""
UPDATE_INTERVAL="6"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
TELEGRAM_THREAD_ID="0"
TELEGRAM_ENABLED="false"
GITHUB_AUTH_METHOD=""

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

MENU_WIDTH=62
MENU_LINE=$(printf '%*s' "$MENU_WIDTH" '' | tr ' ' '_')

menu_header() {
    local title="$1"
    local subtitle="${2:-}"
    [[ -t 0 && -z "${RF_NO_CLEAR:-}" ]] && clear
    echo ""
    echo "${MENU_LINE}"
    echo ""
    local pad=$(( (MENU_WIDTH - ${#title}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf '%*s' "$pad" ''
    echo -e "${BOLD}${title}${NC}"
    if [[ -n "$subtitle" ]]; then
        local sub_pad=$(( (MENU_WIDTH - ${#subtitle}) / 2 ))
        [[ $sub_pad -lt 0 ]] && sub_pad=0
        printf '%*s' "$sub_pad" ''
        echo -e "${LIGHT_GRAY}${subtitle}${NC}"
    fi
    echo ""
    echo "${MENU_LINE}"
}

menu_footer() {
    echo ""
    echo "${MENU_LINE}"
    echo ""
}

menu_item() {
    local key="$1"
    local label="$2"
    echo -e "      ${GREEN}[${key}]${NC}  ${label}"
}

press_enter() {
    echo ""
    read -rp "      Press Enter to continue..."
}

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

    if [[ -L "$SCRIPT_PATH" && "$(readlink -f "$SCRIPT_PATH")" == "$(readlink -f "$0")" ]]; then
        :
    elif [[ -d "$(dirname "$SCRIPT_PATH")" ]]; then
        rm -f "$SCRIPT_PATH"
        if [[ "$(readlink -f "$0")" != "${SCRIPT_PATH}" ]]; then
            cp "$(readlink -f "$0")" "${SCRIPT_PATH}"
            chmod +x "${SCRIPT_PATH}"
        fi
    fi

    if [[ -L "$SYMLINK_PATH" && "$(readlink -f "$SYMLINK_PATH")" == "$SCRIPT_PATH" ]]; then
        :
    elif [[ -d "$(dirname "$SYMLINK_PATH")" ]]; then
        rm -f "$SYMLINK_PATH"
        if ln -s "$SCRIPT_PATH" "$SYMLINK_PATH" 2>/dev/null; then
            :
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
    echo -e "      ${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "      ${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "      ${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "      ${BLUE}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_dependencies() {
    local deps=("curl" "jq" "cron" "git")
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
        apt-get install -y -qq curl jq cron git
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

DOWNLOAD_DIR="${DOWNLOAD_DIR}"
UPDATE_INTERVAL="${UPDATE_INTERVAL}"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID}"
TELEGRAM_ENABLED="${TELEGRAM_ENABLED}"

# Authentication method: ghcli, ssh, or empty
GITHUB_AUTH_METHOD="${GITHUB_AUTH_METHOD}"
EOF
    chmod 600 "${CONFIG_FILE}"
    print_success "Configuration saved"
}

save_urls() {
    printf '%s\n' "${URLS[@]}" > "${URLS_FILE}"
    chmod 644 "${URLS_FILE}"
    print_success "URLs saved"
}

load_urls() {
    URLS=()
    if [[ -f "${URLS_FILE}" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] && URLS+=("$line")
        done < "${URLS_FILE}"
    fi
}

normalize_github_url() {
    local url="$1"
    if [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/blob/(.+)$ ]]; then
        echo "https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
        return
    fi
    echo "$url"
}

get_url_basename() {
    local url="${1%%\?*}"
    basename "${url}"
}

is_github_url() {
    local url="$1"
    [[ "${url}" =~ ^https://(api\.github\.com|github\.com|raw\.githubusercontent\.com)/ ]]
}

is_github_release_asset_url() {
    local url="$1"
    [[ "${url}" =~ ^https://api\.github\.com/repos/[^/]+/[^/]+/releases/assets/[0-9]+([/?].*)?$ ]]
}

check_ghcli_auth() {
    if ! command -v gh &>/dev/null; then
        return 1
    fi
    gh auth status &>/dev/null
    return $?
}

check_ssh_auth() {
    local output
    output=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -T git@github.com 2>&1)
    [[ "$output" == *"successfully authenticated"* ]]
}

get_github_token() {
    if [[ -n "${RULESET_FETCHER_GITHUB_TOKEN:-}" ]]; then
        echo "${RULESET_FETCHER_GITHUB_TOKEN}"
        return
    fi
    if [[ -n "${RF_GITHUB_TOKEN:-}" ]]; then
        echo "${RF_GITHUB_TOKEN}"
        return
    fi
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "${GITHUB_TOKEN}"
        return
    fi

    if command -v gh &>/dev/null; then
        local token
        token=$(gh auth token 2>/dev/null)
        if [[ -n "$token" ]]; then
            echo "$token"
            return
        fi
    fi

    # Legacy: old config token (backward compatibility)
    if [[ -n "${GITHUB_ACCESS_TOKEN:-}" ]]; then
        echo "${GITHUB_ACCESS_TOKEN}"
        return
    fi
}

parse_github_raw_url() {
    local url="${1%%\?*}"
    if [[ "$url" =~ ^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
        return 0
    fi
    if [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/raw/([^/]+)/(.+)$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
        return 0
    fi
    return 1
}

download_file_via_git_ssh() {
    local url="$1"
    local dest_dir="$2"

    local parsed
    parsed=$(parse_github_raw_url "$url") || return 1

    local owner repo ref filepath
    read -r owner repo ref filepath <<< "$parsed"
    local filename
    filename=$(basename "${filepath}")
    local temp_dir
    temp_dir=$(mktemp -d)

    if GIT_SSH_COMMAND="ssh -o ConnectTimeout=10 -o BatchMode=yes" \
        git -C "${temp_dir}" init -q 2>/dev/null \
        && GIT_SSH_COMMAND="ssh -o ConnectTimeout=10 -o BatchMode=yes" \
        git -C "${temp_dir}" remote add origin "git@github.com:${owner}/${repo}.git" 2>/dev/null \
        && GIT_SSH_COMMAND="ssh -o ConnectTimeout=10 -o BatchMode=yes" \
        git -C "${temp_dir}" fetch -q --depth 1 origin "${ref}" 2>/dev/null \
        && GIT_SSH_COMMAND="ssh -o ConnectTimeout=10 -o BatchMode=yes" \
        git -C "${temp_dir}" checkout FETCH_HEAD -- "${filepath}" 2>/dev/null; then

        if [[ -f "${temp_dir}/${filepath}" ]]; then
            mkdir -p "${dest_dir}"
            cp "${temp_dir}/${filepath}" "${dest_dir}/${filename}"
            chmod 644 "${dest_dir}/${filename}"
            rm -rf "${temp_dir}"
            echo "${filename}"
            return 0
        fi
    fi

    rm -rf "${temp_dir}"
    return 1
}

download_github_release_asset() {
    local url="$1"
    local dest_dir="$2"
    local github_token
    github_token="$(get_github_token)"
    local metadata_headers=(-H "Accept: application/vnd.github+json")
    local download_headers=(-H "Accept: application/octet-stream")

    if [[ -n "${github_token}" ]]; then
        metadata_headers+=(-H "Authorization: Bearer ${github_token}")
        download_headers+=(-H "Authorization: Bearer ${github_token}")
    fi

    local metadata
    metadata=$(curl -fsSL --connect-timeout 30 --max-time 120 \
        "${metadata_headers[@]}" \
        "${url}" 2>/dev/null) || {
        if [[ -z "${github_token}" ]]; then
            log_message "ERROR" "GitHub release asset metadata request failed. Authenticate with 'gh auth login' or set up SSH: ${url}"
        fi
        return 1
    }

    local filename
    filename=$(printf '%s' "${metadata}" | jq -r '.name // empty' 2>/dev/null)
    filename="${filename##*/}"

    if [[ -z "${filename}" ]]; then
        log_message "ERROR" "Failed to resolve GitHub asset filename for ${url}"
        return 1
    fi

    local dest_path="${dest_dir}/${filename}"
    local temp_path="${dest_path}.tmp"

    mkdir -p "${dest_dir}"

    if curl -fsSL --connect-timeout 30 --max-time 300 \
        "${download_headers[@]}" \
        -o "${temp_path}" "${url}" 2>/dev/null; then
        mv "${temp_path}" "${dest_path}"
        chmod 644 "${dest_path}"
        echo "${filename}"
        return 0
    fi

    if [[ -z "${github_token}" ]]; then
        log_message "ERROR" "GitHub release asset download failed. Authenticate with 'gh auth login' or set up SSH: ${url}"
    fi

    rm -f "${temp_path}" 2>/dev/null
    return 1
}

download_file() {
    local url="$1"
    local dest_dir="$2"
    local filename
    filename="$(get_url_basename "${url}")"
    local dest_path="${dest_dir}/${filename}"
    local temp_path="${dest_path}.tmp"
    local github_token
    github_token="$(get_github_token)"
    local curl_args=(
        -fsSL
        --connect-timeout 30
        --max-time 120
        -o "${temp_path}"
    )

    if is_github_release_asset_url "${url}"; then
        download_github_release_asset "${url}" "${dest_dir}"
        return $?
    fi

    if is_github_url "${url}" && [[ -n "${github_token}" ]]; then
        curl_args+=(-H "Authorization: Bearer ${github_token}")
    fi

    mkdir -p "${dest_dir}"

    if curl "${curl_args[@]}" "${url}" 2>/dev/null; then
        mv "${temp_path}" "${dest_path}"
        chmod 644 "${dest_path}"
        echo "${filename}"
        return 0
    fi

    rm -f "${temp_path}" 2>/dev/null

    if is_github_url "${url}" && [[ "${GITHUB_AUTH_METHOD}" == "ssh" ]]; then
        if download_file_via_git_ssh "${url}" "${dest_dir}"; then
            return 0
        fi
    fi

    return 1
}

download_all_files() {
    local silent_mode="${1:-false}"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        print_error "Configuration not found. Please run setup first."
        return 1
    fi

    load_config
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
        local filename
        filename="$(get_url_basename "${url}")"
        [[ "$silent_mode" != "true" ]] && echo -n "      Downloading ${filename}... "

        if result=$(download_file "$url" "$DOWNLOAD_DIR"); then
            local downloaded_name="${result:-${filename}}"
            ((success_count++))
            success_files+=("${downloaded_name}")
            [[ "$silent_mode" != "true" ]] && echo -e "${GREEN}OK${NC}"
            log_message "INFO" "Downloaded: ${downloaded_name}"
        else
            ((fail_count++))
            failed_files+=("$filename")
            [[ "$silent_mode" != "true" ]] && echo -e "${RED}FAILED${NC}"
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

CRON_MARKER="# ruleset-fetcher-auto-update"

install_cron_job() {
    local interval_hours="$1"

    remove_cron_job 2>/dev/null || true

    local cron_expr
    case "$interval_hours" in
        1)  cron_expr="0 * * * *" ;;
        3)  cron_expr="0 */3 * * *" ;;
        6)  cron_expr="0 */6 * * *" ;;
        12) cron_expr="0 */12 * * *" ;;
        24) cron_expr="0 0 * * *" ;;
        *)  cron_expr="0 */${interval_hours} * * *" ;;
    esac

    local existing_cron
    existing_cron=$(crontab -l 2>/dev/null) || existing_cron=""

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
        print_success "Auto-update cron job is ${BOLD}ACTIVE${NC}"
        echo ""
        echo "      Schedule: ${cron_line% $CRON_MARKER}"
    else
        print_warning "Auto-update cron job is ${BOLD}NOT ACTIVE${NC}"
    fi
}

setup_download_directory() {
    echo ""
    echo "${MENU_LINE}"
    echo ""
    local title="Download Directory"
    local pad=$(( (MENU_WIDTH - ${#title}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf '%*s' "$pad" ''
    echo -e "${BOLD}${title}${NC}"
    echo ""
    echo "${MENU_LINE}"
    echo ""

    local default_dir="${CONFIG_DIR}"
    echo "      Where should downloaded files be saved?"
    echo ""
    echo -e "      Default: ${BOLD}${default_dir}${NC}"
    echo ""
    read -rp "      Path [Enter for default]: " input_dir
    DOWNLOAD_DIR="${input_dir:-$default_dir}"

    if [[ ! -d "${DOWNLOAD_DIR}" ]]; then
        mkdir -p "${DOWNLOAD_DIR}"
        chmod 755 "${DOWNLOAD_DIR}"
        print_success "Created directory: ${DOWNLOAD_DIR}"
    else
        print_success "Using directory: ${DOWNLOAD_DIR}"
    fi
}

setup_urls() {
    echo ""
    echo "${MENU_LINE}"
    echo ""
    local title="Download URLs"
    local pad=$(( (MENU_WIDTH - ${#title}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf '%*s' "$pad" ''
    echo -e "${BOLD}${title}${NC}"
    echo ""
    echo "${MENU_LINE}"
    echo ""
    echo "      Enter the URLs of files to download (one per line)."
    echo "      Press Enter on empty line when done."
    echo ""

    URLS=()

    while true; do
        read -r -p "      URL: " url || true
        if [[ -z "$url" ]]; then
            break
        fi
        if [[ "$url" =~ ^https?:// ]]; then
            url=$(normalize_github_url "$url")
            URLS+=("$url")
            print_success "Added: $(get_url_basename "$url")"
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
    echo "      How often should files be updated?"
    echo ""
    menu_item "1" "Every 1 hour"
    menu_item "2" "Every 3 hours"
    menu_item "3" "Every 6 hours  ${LIGHT_GRAY}(default)${NC}"
    menu_item "4" "Every 12 hours"
    menu_item "5" "Every 24 hours"
    menu_item "6" "Custom interval"
    echo ""

    read -rp "      Select [3]: " interval_option
    interval_option="${interval_option:-3}"

    case "$interval_option" in
        1) UPDATE_INTERVAL=1 ;;
        2) UPDATE_INTERVAL=3 ;;
        3) UPDATE_INTERVAL=6 ;;
        4) UPDATE_INTERVAL=12 ;;
        5) UPDATE_INTERVAL=24 ;;
        6)
            read -rp "      Enter custom interval in hours: " custom_interval
            if [[ "${custom_interval}" =~ ^[1-9][0-9]*$ ]]; then
                UPDATE_INTERVAL="${custom_interval}"
            else
                print_warning "Invalid interval. Using default: 6 hours"
                UPDATE_INTERVAL=6
            fi
            ;;
        *) UPDATE_INTERVAL=6 ;;
    esac

    print_success "Update interval set to ${UPDATE_INTERVAL} hour(s)"
}

show_auth_status() {
    local ghcli_ok=false
    local ssh_ok=false

    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null; then
            local ghcli_user
            ghcli_user=$(gh auth status 2>&1 | grep -oP 'Logged in to [^ ]+ account \K\S+' || echo "")
            ghcli_user="${ghcli_user%% *}"
            print_success "GitHub CLI: authenticated${ghcli_user:+ as ${BOLD}${ghcli_user}${NC}}"
            ghcli_ok=true
        else
            print_warning "GitHub CLI: installed but not authenticated"
        fi
    else
        print_info "GitHub CLI: not installed"
    fi

    local ssh_output
    ssh_output=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -T git@github.com 2>&1)
    if [[ "$ssh_output" == *"successfully authenticated"* ]]; then
        local ssh_user
        ssh_user=$(echo "$ssh_output" | grep -oP 'Hi \K[^!]+' || echo "")
        print_success "SSH: connected${ssh_user:+ as ${BOLD}${ssh_user}${NC}}"
        ssh_ok=true
    elif ls ~/.ssh/id_* &>/dev/null 2>&1; then
        print_warning "SSH: key found but not linked to GitHub"
    else
        print_info "SSH: no key found"
    fi

    if $ghcli_ok || $ssh_ok; then
        return 0
    fi
    return 1
}

do_setup_ghcli() {
    echo ""
    echo "${MENU_LINE}"
    echo ""
    local title="GitHub CLI Setup"
    local pad=$(( (MENU_WIDTH - ${#title}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf '%*s' "$pad" ''
    echo -e "${BOLD}${title}${NC}"
    echo ""
    echo "${MENU_LINE}"
    echo ""

    if ! command -v gh &>/dev/null; then
        print_warning "GitHub CLI is not installed."
        echo ""
        read -rp "      Install GitHub CLI now? (y/n) [y]: " install_gh
        install_gh="${install_gh:-y}"

        if [[ "$install_gh" =~ ^[Yy]$ ]]; then
            echo ""
            print_info "Installing GitHub CLI..."
            echo ""
            local install_ok=false
            if command -v apt-get &>/dev/null; then
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null \
                    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
                    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
                    && apt-get update -qq \
                    && apt-get install -y -qq gh \
                    && install_ok=true
            elif command -v dnf &>/dev/null; then
                dnf install -y -q gh && install_ok=true
            elif command -v brew &>/dev/null; then
                brew install gh && install_ok=true
            else
                print_error "Could not detect package manager."
                echo ""
                echo "      Install manually:"
                echo -e "        ${CYAN}https://cli.github.com${NC}"
                echo ""
                press_enter
                return
            fi

            hash -r
            if $install_ok && command -v gh &>/dev/null; then
                print_success "GitHub CLI installed!"
            else
                print_error "Installation failed."
                echo ""
                echo "      Install manually:"
                echo -e "        ${CYAN}https://cli.github.com${NC}"
                echo ""
                press_enter
                return
            fi
        else
            print_info "Skipped. You can install later."
            echo ""
            echo "      Install commands:"
            echo -e "        ${CYAN}Debian / Ubuntu:${NC}  sudo apt install gh"
            echo -e "        ${CYAN}Fedora / RHEL:${NC}    sudo dnf install gh"
            echo -e "        ${CYAN}macOS:${NC}            brew install gh"
            echo -e "        ${CYAN}Other:${NC}            https://cli.github.com"
            echo ""
            press_enter
            return
        fi
    fi

    if gh auth status &>/dev/null; then
        print_success "GitHub CLI is already authenticated!"
        return
    fi

    echo ""
    read -rp "      Start authentication now? (y/n) [y]: " do_auth
    do_auth="${do_auth:-y}"

    if [[ "$do_auth" =~ ^[Yy]$ ]]; then
        echo ""
        gh auth login

        if gh auth status &>/dev/null; then
            echo ""
            print_success "GitHub CLI authenticated!"
        else
            echo ""
            print_warning "Authentication was not completed."
            print_info "You can try again later with: gh auth login"
        fi
    else
        print_info "Skipped. Authenticate later with: gh auth login"
    fi
}

do_setup_ssh() {
    echo ""
    echo "${MENU_LINE}"
    echo ""
    local title="SSH Key Setup"
    local pad=$(( (MENU_WIDTH - ${#title}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf '%*s' "$pad" ''
    echo -e "${BOLD}${title}${NC}"
    echo ""
    echo "${MENU_LINE}"
    echo ""

    if ! ls ~/.ssh/id_* &>/dev/null 2>&1; then
        echo "      1. Generate an SSH key:"
        echo ""
        echo -e "           ${BOLD}ssh-keygen -t ed25519${NC}"
        echo ""
    else
        echo "      SSH key found."
        echo ""
    fi

    echo "      2. Copy your public key:"
    echo ""
    echo -e "           ${BOLD}cat ~/.ssh/id_ed25519.pub${NC}"
    echo ""
    echo "      3. Add it to GitHub:"
    echo ""
    echo -e "           ${CYAN}https://github.com/settings/ssh/new${NC}"
    echo ""
    echo "      4. Test the connection:"
    echo ""
    echo -e "           ${BOLD}ssh -T git@github.com${NC}"
    echo ""
    echo -e "      ${LIGHT_GRAY}Note: for GitHub release assets, GitHub CLI"
    echo -e "      is recommended instead of SSH.${NC}"
    echo ""
    press_enter

    local ssh_output
    ssh_output=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -T git@github.com 2>&1)
    if [[ "$ssh_output" == *"successfully authenticated"* ]]; then
        print_success "SSH authentication successful!"
    else
        print_warning "SSH not yet configured for GitHub."
        print_info "Follow the instructions above to set it up."
    fi
}

setup_auth() {
    echo ""
    echo "${MENU_LINE}"
    echo ""
    local title="GitHub Authentication"
    local pad=$(( (MENU_WIDTH - ${#title}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf '%*s' "$pad" ''
    echo -e "${BOLD}${title}${NC}"
    echo ""
    echo "${MENU_LINE}"
    echo ""

    echo "      Checking current status..."
    echo ""

    local auth_ok=false
    if show_auth_status; then
        auth_ok=true
    fi

    echo ""

    if $auth_ok; then
        echo "      Authentication is already configured."
        echo ""
        menu_item "1" "Keep current setup"
        menu_item "2" "Setup GitHub CLI"
        menu_item "3" "Setup SSH key"
        echo ""

        local choice
        read -rp "      Select [1]: " choice
        choice="${choice:-1}"

        case $choice in
            1)
                if check_ghcli_auth; then
                    GITHUB_AUTH_METHOD="ghcli"
                elif check_ssh_auth; then
                    GITHUB_AUTH_METHOD="ssh"
                fi
                ;;
            2) do_setup_ghcli; GITHUB_AUTH_METHOD="ghcli" ;;
            3) do_setup_ssh; GITHUB_AUTH_METHOD="ssh" ;;
        esac
    else
        echo "      Authentication is needed for private repositories."
        echo "      For public repos, you can skip this step."
        echo ""
        menu_item "1" "GitHub CLI  ${LIGHT_GRAY}(recommended)${NC}"
        menu_item "2" "SSH key"
        menu_item "3" "Skip  ${LIGHT_GRAY}(public repos only)${NC}"
        echo ""

        local choice
        read -rp "      Select [1]: " choice
        choice="${choice:-1}"

        case $choice in
            1) do_setup_ghcli; GITHUB_AUTH_METHOD="ghcli" ;;
            2) do_setup_ssh; GITHUB_AUTH_METHOD="ssh" ;;
            3) GITHUB_AUTH_METHOD=""; print_info "Skipped. Public repositories only." ;;
        esac
    fi
}

setup_telegram() {
    echo ""
    read -rp "      Enable Telegram notifications? (y/n) [y]: " enable_tg
    enable_tg="${enable_tg:-y}"

    if [[ "$enable_tg" =~ ^[Yy]$ ]]; then
        TELEGRAM_ENABLED="true"
        echo ""
        echo "      To set up Telegram notifications:"
        echo "        1. Create a bot via @BotFather → get bot token"
        echo "        2. Get your chat ID from @userinfobot"
        echo "        3. For forum groups, get the thread ID"
        echo ""

        read -rp "      Bot Token: " TELEGRAM_BOT_TOKEN
        read -rp "      Chat ID: " TELEGRAM_CHAT_ID

        echo ""
        read -rp "      Thread ID (Enter to skip): " TELEGRAM_THREAD_ID
        TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-0}"

        if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
            echo ""
            read -rp "      Send test notification? (y/n) [y]: " send_test
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
    if [[ -t 0 && -z "${RF_NO_CLEAR:-}" ]]; then
        clear
    fi
    print_banner
    check_root
    check_dependencies
    create_config_dir

    echo ""
    print_info "Starting Setup Wizard..."

    setup_auth

    setup_download_directory

    setup_urls

    if [[ ${#URLS[@]} -gt 0 ]]; then
        echo ""
        echo "${MENU_LINE}"
        echo ""
        local title="Review URLs"
        local pad=$(( (MENU_WIDTH - ${#title}) / 2 ))
        [[ $pad -lt 0 ]] && pad=0
        printf '%*s' "$pad" ''
        echo -e "${BOLD}${title}${NC}"
        echo ""
        echo "${MENU_LINE}"
        echo ""

        echo "      You have added ${#URLS[@]} URL(s):"
        echo ""
        local i=1
        for url in "${URLS[@]}"; do
            echo "        ${i}) $(get_url_basename "$url")"
            ((i++))
        done
        echo ""

        while true; do
            read -rp "      Modify the list? (y/n) [n]: " modify_urls
            modify_urls="${modify_urls:-n}"

            if [[ "$modify_urls" =~ ^[Yy]$ ]]; then
                echo ""
                menu_item "1" "Add more URLs"
                menu_item "2" "Remove a URL"
                menu_item "3" "Clear all and re-enter"
                menu_item "0" "Done editing"
                echo ""
                read -rp "      Select: " edit_option

                case "$edit_option" in
                    1)
                        echo ""
                        echo "      Enter additional URLs (Enter on empty line to stop):"
                        while true; do
                            read -rp "      URL: " url
                            if [[ -z "$url" ]]; then
                                break
                            fi
                            if [[ "$url" =~ ^https?:// ]]; then
                                url=$(normalize_github_url "$url")
                                URLS+=("$url")
                                print_success "Added: $(get_url_basename "$url")"
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
                                echo "        ${j}) $(get_url_basename "$url")"
                                ((j++))
                            done
                            echo ""
                            read -rp "      Enter number to remove: " remove_num
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

                if [[ ${#URLS[@]} -gt 0 ]]; then
                    echo ""
                    echo "      Current URLs (${#URLS[@]} total):"
                    local k=1
                    for url in "${URLS[@]}"; do
                        echo "        ${k}) $(get_url_basename "$url")"
                        ((k++))
                    done
                fi
            else
                break
            fi
        done

        echo ""
        read -rp "      Download files now? (y/n) [y]: " download_now
        download_now="${download_now:-y}"
        if [[ "$download_now" =~ ^[Yy]$ ]]; then
            save_config
            save_urls
            echo ""
            download_all_files
        fi
    fi

    echo ""
    echo "${MENU_LINE}"
    echo ""
    local tg_title="Telegram Notifications"
    local tg_pad=$(( (MENU_WIDTH - ${#tg_title}) / 2 ))
    [[ $tg_pad -lt 0 ]] && tg_pad=0
    printf '%*s' "$tg_pad" ''
    echo -e "${BOLD}${tg_title}${NC}"
    echo ""
    echo "${MENU_LINE}"
    echo ""
    read -rp "      Configure Telegram notifications? (y/n) [n]: " setup_tg_now
    setup_tg_now="${setup_tg_now:-n}"

    if [[ "$setup_tg_now" =~ ^[Yy]$ ]]; then
        setup_telegram
    else
        TELEGRAM_ENABLED="false"
        TELEGRAM_BOT_TOKEN=""
        TELEGRAM_CHAT_ID=""
        TELEGRAM_THREAD_ID="0"
        print_info "Skipped. You can configure later from the menu."
    fi

    echo ""
    echo "${MENU_LINE}"
    echo ""
    local interval_title="Auto-Update Interval"
    local interval_pad=$(( (MENU_WIDTH - ${#interval_title}) / 2 ))
    [[ $interval_pad -lt 0 ]] && interval_pad=0
    printf '%*s' "$interval_pad" ''
    echo -e "${BOLD}${interval_title}${NC}"
    echo ""
    echo "${MENU_LINE}"

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

    menu_footer
    print_success "Setup complete!"
    echo ""
    echo "      Quick access commands:"
    echo -e "        ${BOLD}ruleset-fetcher${NC}  - Full command"
    echo -e "        ${BOLD}rfetcher${NC}         - Short alias"
    echo ""
    echo "      Files are saved to: ${DOWNLOAD_DIR}"
    echo "      Auto-update every: ${UPDATE_INTERVAL} hour(s)"
    menu_footer
    read -rp "      Press Enter to continue..."
}

add_url() {
    load_urls

    echo ""
    read -rp "      Enter URL to add: " new_url

    if [[ -z "$new_url" ]]; then
        print_error "No URL provided"
        return 1
    fi

    if [[ ! "$new_url" =~ ^https?:// ]]; then
        print_error "Invalid URL format"
        return 1
    fi

    new_url=$(normalize_github_url "$new_url")

    for url in "${URLS[@]}"; do
        if [[ "$url" == "$new_url" ]]; then
            print_warning "URL already exists"
            return 1
        fi
    done

    URLS+=("$new_url")
    save_urls
    print_success "Added: $(get_url_basename "$new_url")"
}

remove_url() {
    load_urls

    if [[ ${#URLS[@]} -eq 0 ]]; then
        print_error "No URLs configured"
        return 1
    fi

    echo ""
    echo "      Current URLs:"
    local i=1
    for url in "${URLS[@]}"; do
        echo "        ${i}) $(get_url_basename "$url")"
        ((i++))
    done

    echo ""
    read -rp "      Enter number to remove (or 'all'): " selection

    if [[ "$selection" == "all" ]]; then
        URLS=()
        save_urls
        print_success "All URLs removed"
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#URLS[@]} ]]; then
        local removed="${URLS[$((selection-1))]}"
        unset 'URLS[$((selection-1))]'
        URLS=("${URLS[@]}")
        save_urls
        print_success "Removed: $(get_url_basename "$removed")"
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
        echo "        ${i}) $(get_url_basename "$url")"
        echo "           ${url}"
        ((i++))
    done
    echo ""
}

show_status() {
    echo ""
    echo "      ${BOLD}Configuration${NC}"
    echo "      ${MENU_LINE}"
    echo ""

    if load_config; then
        echo "      Download Directory:  ${DOWNLOAD_DIR}"
        echo "      Update Interval:     ${UPDATE_INTERVAL} hour(s)"

        echo -n "      GitHub Auth:         "
        case "${GITHUB_AUTH_METHOD}" in
            ghcli) echo "GitHub CLI" ;;
            ssh)   echo "SSH" ;;
            *)     echo "none" ;;
        esac

        echo "      Telegram:            ${TELEGRAM_ENABLED}"

        load_urls
        echo "      Configured URLs:     ${#URLS[@]}"

        if [[ -d "${DOWNLOAD_DIR}" ]]; then
            local file_count=$(find "${DOWNLOAD_DIR}" -maxdepth 1 -type f \
                ! -name "$(basename "${CONFIG_FILE}")" \
                ! -name "$(basename "${URLS_FILE}")" \
                ! -name "$(basename "${LOG_FILE}")" 2>/dev/null | wc -l)
            echo "      Downloaded Files:    ${file_count}"
        fi
    else
        print_warning "Not configured. Run with --setup to configure."
    fi

    echo ""
    echo "      ${BOLD}Cron Status${NC}"
    echo "      ${MENU_LINE}"
    echo ""
    show_cron_status

    echo ""
    echo "      ${BOLD}Recent Logs${NC}"
    echo "      ${MENU_LINE}"
    echo ""
    if [[ -f "${LOG_FILE}" ]]; then
        tail -10 "${LOG_FILE}" | while IFS= read -r line; do
            echo "      ${line}"
        done
    else
        echo "      No logs yet"
    fi
}

get_remote_version() {
    local remote_script
    remote_script=$(curl -fsSL --connect-timeout 10 --max-time 30 "${GITHUB_RAW_URL}" 2>/dev/null) || return 1

    local version
    version=$(printf '%s\n' "$remote_script" \
        | sed -nE "s/^[[:space:]]*VERSION[[:space:]]*=[[:space:]]*['\"]?([^[:space:]'\"]+)['\"]?.*/\1/p" \
        | head -n1)

    if [[ -z "$version" ]]; then
        print_error "Failed to parse remote version"
        return 1
    fi

    if ! [[ "$version" =~ ^v?[0-9]+(\.[0-9]+)*$ ]]; then
        print_error "Invalid version format: '$version'"
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
        print_error "Failed to check for updates."
        return 1
    fi

    echo ""
    echo "      Current version:  ${VERSION}"
    echo "      Latest version:   ${remote_version}"
    echo ""

    compare_versions "$VERSION" "$remote_version"
    local result=$?

    if [[ $result -eq 0 ]]; then
        print_success "You are running the latest version!"
    elif [[ $result -eq 2 ]]; then
        print_warning "A new version is available: v${remote_version}"
        echo ""
        echo "      Run 'sudo ruleset-fetcher --self-update' to update"
    else
        print_info "You are running a newer version than released."
    fi
}

self_update() {
    echo ""
    print_info "Checking for updates..."

    if [[ -f "${SCRIPT_PATH}.backup" ]]; then
        local backup_timestamp
        backup_timestamp=$(stat -c %Y "${SCRIPT_PATH}.backup" 2>/dev/null || stat -f %m "${SCRIPT_PATH}.backup" 2>/dev/null)

        if [[ -n "$backup_timestamp" && "$backup_timestamp" =~ ^[0-9]+$ ]]; then
            local backup_age_seconds=$(( $(date +%s) - backup_timestamp ))
            local one_day_seconds=$((24 * 60 * 60))

            if [[ $backup_age_seconds -gt $one_day_seconds ]]; then
                rm -f "${SCRIPT_PATH}.backup"
                log_message "INFO" "Removed old backup file (${backup_age_seconds}s old)"
            fi
        fi
    fi

    local remote_version
    remote_version=$(get_remote_version)

    if [[ -z "$remote_version" ]]; then
        print_error "Failed to check for updates."
        return 1
    fi

    compare_versions "$VERSION" "$remote_version"
    local result=$?

    if [[ $result -eq 0 ]]; then
        print_success "Already running the latest version (v${VERSION})"
        return 0
    elif [[ $result -eq 1 ]]; then
        print_info "Running newer version (v${VERSION}) than released (v${remote_version})"
        read -rp "      Downgrade to released version? (y/n) [n]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Update cancelled"
            return 0
        fi
    else
        echo ""
        echo "      Current version:  ${VERSION}"
        echo "      Latest version:   ${remote_version}"
        echo ""
        read -rp "      Update to v${remote_version}? (y/n) [y]: " confirm
        confirm="${confirm:-y}"
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Update cancelled"
            return 0
        fi
    fi

    print_info "Downloading update..."

    local temp_file
    temp_file="$(mktemp -t ruleset-fetcher-update.XXXXXX)" || {
        print_error "Failed to create temporary file"
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
            print_error "Current script is not readable; aborting."
            rm -f "${temp_file}"
            return 1
        fi
        if ! cp "${SCRIPT_PATH}" "${SCRIPT_PATH}.backup"; then
            print_error "Failed to create backup; aborting."
            rm -f "${temp_file}"
            return 1
        fi
        had_backup=true
    fi

    if ! mv "${temp_file}" "${SCRIPT_PATH}"; then
        print_error "Failed to install update"
        if [[ "${had_backup}" == true ]]; then
            if mv "${SCRIPT_PATH}.backup" "${SCRIPT_PATH}"; then
                print_info "Restored previous version from backup."
            else
                print_error "Failed to restore from backup at ${SCRIPT_PATH}.backup"
            fi
        fi
        rm -f "${temp_file}"
        return 1
    fi

    if ! chmod +x "${SCRIPT_PATH}"; then
        print_error "Failed to make updated script executable"
        if [[ "${had_backup}" == true ]]; then
            if mv "${SCRIPT_PATH}.backup" "${SCRIPT_PATH}"; then
                print_info "Restored previous version from backup."
            else
                print_error "Failed to restore from backup at ${SCRIPT_PATH}.backup"
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
    echo "GitHub authentication:"
    echo "  GitHub CLI:  gh auth login    (recommended)"
    echo "  SSH key:     ssh-keygen + add to GitHub"
    echo "  Env vars:    GITHUB_TOKEN / RF_GITHUB_TOKEN"
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
    read -rp "      Are you sure? (y/n) [n]: " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local download_dir=""
        if [[ -f "${CONFIG_FILE}" ]]; then
            load_config
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
                local file_count=$(find "${download_dir}" -type f \
                    ! -name "$(basename "${CONFIG_FILE}")" \
                    ! -name "$(basename "${URLS_FILE}")" \
                    ! -name "$(basename "${LOG_FILE}")" 2>/dev/null | wc -l)
                if [[ $file_count -gt 0 ]]; then
                    echo ""
                    print_info "Found ${file_count} downloaded file(s) in: ${download_dir}"
                    read -rp "      Remove downloaded files too? (y/n) [n]: " remove_files

                    if [[ "$remove_files" =~ ^[Yy]$ ]]; then
                        rm -rf "${download_dir}"
                        print_success "Downloaded files removed"
                    else
                        print_info "Downloaded files kept in: ${download_dir}"
                        if [[ "${download_dir}" == "${CONFIG_DIR}" ]]; then
                            rm -f "${CONFIG_FILE}" "${URLS_FILE}" "${LOG_FILE}"
                        fi
                    fi
                fi
            else
                print_warning "Downloaded files in ${download_dir} were not removed (system directory)"
            fi
        fi

        if [[ -d "${CONFIG_DIR}" ]] && [[ "${CONFIG_DIR}" != "${download_dir}" ]]; then
            rm -rf "${CONFIG_DIR}"
        fi

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
        menu_header "Ruleset Fetcher" "v${VERSION}"
        echo ""
        menu_item "1" "Download/update files"
        menu_item "2" "Manage URLs"
        menu_item "3" "Show status"
        echo ""
        menu_item "4" "GitHub authentication"
        menu_item "5" "Telegram notifications"
        menu_item "6" "Auto-update schedule"
        echo ""
        menu_item "7" "Check for script updates"
        menu_item "8" "Update script"
        menu_item "9" "Uninstall"
        echo ""
        menu_item "0" "Exit"
        menu_footer

        local choice
        read -rp "      Enter a menu option: " choice

        case $choice in
            1)
                echo ""
                download_all_files
                press_enter
                ;;
            2)
                manage_urls_menu
                ;;
            3)
                menu_header "Status"
                show_status
                press_enter
                ;;
            4)
                configure_github_menu
                ;;
            5)
                configure_telegram_menu
                ;;
            6)
                configure_timer_menu
                ;;
            7)
                check_for_updates
                press_enter
                ;;
            8)
                self_update
                press_enter
                ;;
            9)
                uninstall
                if [[ ! -f "${CONFIG_FILE}" ]]; then
                    exit 0
                fi
                ;;
            0)
                echo ""
                echo "      Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                print_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

manage_urls_menu() {
    while true; do
        menu_header "Manage URLs"

        load_urls
        if [[ ${#URLS[@]} -gt 0 ]]; then
            print_info "Current URLs (${#URLS[@]} total):"
            echo ""
            local i=1
            for url in "${URLS[@]}"; do
                echo "        ${i}) $(get_url_basename "$url")"
                ((i++))
            done
        else
            print_warning "No URLs configured"
        fi

        echo ""
        menu_item "1" "Add URL"
        menu_item "2" "Remove URL"
        menu_item "3" "List URLs (full paths)"
        echo ""
        menu_item "0" "Back"
        menu_footer

        local choice
        read -rp "      Enter a menu option: " choice

        case $choice in
            1)
                add_url
                press_enter
                ;;
            2)
                remove_url
                press_enter
                ;;
            3)
                list_urls
                press_enter
                ;;
            0)
                break
                ;;
            *)
                print_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

configure_github_menu() {
    while true; do
        menu_header "GitHub Authentication"

        load_config 2>/dev/null || true

        echo "      Checking status..."
        echo ""
        show_auth_status || true

        echo ""
        menu_item "1" "Setup GitHub CLI"
        menu_item "2" "Setup SSH key"
        menu_item "3" "Check status"
        echo ""
        menu_item "0" "Back"
        menu_footer

        local choice
        read -rp "      Enter a menu option: " choice

        case $choice in
            1)
                do_setup_ghcli
                GITHUB_AUTH_METHOD="ghcli"
                save_config
                press_enter
                ;;
            2)
                do_setup_ssh
                GITHUB_AUTH_METHOD="ssh"
                save_config
                press_enter
                ;;
            3)
                echo ""
                show_auth_status || true
                echo ""
                echo -n "      Config method: "
                case "${GITHUB_AUTH_METHOD}" in
                    ghcli) echo "GitHub CLI" ;;
                    ssh)   echo "SSH" ;;
                    *)     echo "not configured" ;;
                esac
                press_enter
                ;;
            0)
                break
                ;;
            *)
                print_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

configure_telegram_menu() {
    while true; do
        menu_header "Telegram Notifications"

        if load_config 2>/dev/null; then
            if [[ "${TELEGRAM_ENABLED}" == "true" ]]; then
                print_success "Status: ${BOLD}ENABLED${NC}"
                if [[ -n "${TELEGRAM_BOT_TOKEN}" ]]; then
                    print_info "Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}..."
                fi
                if [[ -n "${TELEGRAM_CHAT_ID}" ]]; then
                    print_info "Chat ID: ${TELEGRAM_CHAT_ID}"
                fi
                if [[ -n "${TELEGRAM_THREAD_ID}" ]] && [[ "${TELEGRAM_THREAD_ID}" != "0" ]]; then
                    print_info "Thread ID: ${TELEGRAM_THREAD_ID}"
                fi
            else
                print_warning "Status: ${BOLD}DISABLED${NC}"
            fi
        else
            print_warning "Configuration not found"
        fi

        echo ""
        menu_item "1" "Configure settings"
        menu_item "2" "Send test message"
        menu_item "3" "Enable notifications"
        menu_item "4" "Disable notifications"
        echo ""
        menu_item "0" "Back"
        menu_footer

        local choice
        read -rp "      Enter a menu option: " choice

        case $choice in
            1)
                setup_telegram
                save_config
                press_enter
                ;;
            2)
                test_telegram
                press_enter
                ;;
            3)
                TELEGRAM_ENABLED="true"
                save_config
                print_success "Telegram notifications enabled"
                press_enter
                ;;
            4)
                TELEGRAM_ENABLED="false"
                save_config
                print_success "Telegram notifications disabled"
                press_enter
                ;;
            0)
                break
                ;;
            *)
                print_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

configure_timer_menu() {
    while true; do
        menu_header "Auto-Update Schedule"

        if load_config 2>/dev/null; then
            print_info "Interval: every ${UPDATE_INTERVAL} hour(s)"
        fi

        echo ""
        show_cron_status

        echo ""
        menu_item "1" "Change interval"
        menu_item "2" "Enable cron job"
        menu_item "3" "Disable cron job"
        echo ""
        menu_item "0" "Back"
        menu_footer

        local choice
        read -rp "      Enter a menu option: " choice

        case $choice in
            1)
                setup_update_interval
                save_config
                install_cron_job "${UPDATE_INTERVAL}"
                press_enter
                ;;
            2)
                load_config
                install_cron_job "${UPDATE_INTERVAL}"
                press_enter
                ;;
            3)
                remove_cron_job
                press_enter
                ;;
            0)
                break
                ;;
            *)
                print_error "Invalid option"
                press_enter
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
