#!/bin/bash

VERSION="26.2.10"
GITHUB_REPO="prettyleaf/ruleset-fetcher"
GITHUB_BRANCH="dev"
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

RF_MODULES=(ui config auth download telegram cron update setup menus)

# Resolve script location (fails gracefully in bash -c / pipe context)
SCRIPT_REAL_PATH=""
SCRIPT_DIR=""
if [[ -n "${0:-}" ]] && [[ -f "$0" ]]; then
    _rf_self="$(readlink -f -- "$0" 2>/dev/null)" || _rf_self=""
    if [[ -n "${_rf_self}" ]] && grep -q 'RF_MODULES=' "${_rf_self}" 2>/dev/null; then
        SCRIPT_REAL_PATH="${_rf_self}"
        SCRIPT_DIR="$(dirname "${SCRIPT_REAL_PATH}")"
    fi
    unset _rf_self
fi

# Find or bootstrap module library
if [[ -n "${SCRIPT_DIR}" ]] && [[ -d "${SCRIPT_DIR}/lib" ]]; then
    LIB_DIR="${SCRIPT_DIR}/lib"
elif ls "${CONFIG_DIR}/lib/"*.sh &>/dev/null; then
    LIB_DIR="${CONFIG_DIR}/lib"
else
    echo "Downloading modules..." >&2
    mkdir -p "${CONFIG_DIR}/lib"

    _rf_ref="v${VERSION}"
    _rf_probe="https://raw.githubusercontent.com/${GITHUB_REPO}/${_rf_ref}/lib/ui.sh"
    if ! curl -fsSL --connect-timeout 5 --max-time 10 -o /dev/null "${_rf_probe}" 2>/dev/null; then
        _rf_ref="${GITHUB_BRANCH}"
    fi

    for _rf_mod in "${RF_MODULES[@]}"; do
        _rf_url="https://raw.githubusercontent.com/${GITHUB_REPO}/${_rf_ref}/lib/${_rf_mod}.sh"
        if ! curl -fsSL --connect-timeout 30 --max-time 60 -o "${CONFIG_DIR}/lib/${_rf_mod}.sh" "${_rf_url}" 2>/dev/null; then
            echo "Error: Failed to download ${_rf_mod}.sh from ${_rf_url}" >&2
            echo "Try re-running: sudo ruleset-fetcher --setup" >&2
            exit 1
        fi
    done

    if [[ -z "${SCRIPT_REAL_PATH}" ]]; then
        _rf_main_url="https://raw.githubusercontent.com/${GITHUB_REPO}/${_rf_ref}/ruleset-fetcher.sh"
        if curl -fsSL --connect-timeout 30 --max-time 60 -o "${CONFIG_DIR}/ruleset-fetcher.sh" "${_rf_main_url}" 2>/dev/null; then
            chmod +x "${CONFIG_DIR}/ruleset-fetcher.sh"
            SCRIPT_REAL_PATH="${CONFIG_DIR}/ruleset-fetcher.sh"
            SCRIPT_DIR="${CONFIG_DIR}"
        fi
    fi

    unset _rf_ref _rf_mod _rf_url _rf_probe _rf_main_url
    LIB_DIR="${CONFIG_DIR}/lib"
fi

for _rf_mod in "${RF_MODULES[@]}"; do
    source "${LIB_DIR}/${_rf_mod}.sh" || { echo "Error: Failed to load ${_rf_mod}.sh" >&2; exit 1; }
done
unset _rf_mod

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
