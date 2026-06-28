#!/bin/bash
# Configuration management: load/save config, URL management

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
