#!/bin/bash
# UI functions: colors, menu rendering, print helpers

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
    local ver_text="v${VERSION}"
    local ver_pad=$(( (MENU_WIDTH - ${#ver_text}) / 2 ))
    [[ $ver_pad -lt 0 ]] && ver_pad=0
    echo -e "${CYAN}"
    echo '            _                _      __      _       _'
    echo ' _ __ _   _| | ___  ___  ___| |_   / _| ___| |_ ___| |__   ___ _ __'
    echo '| '\''__| | | | |/ _ \/ __|/ _ \ __| | |_ / _ \ __/ __| '\''_ \ / _ \ '\''__|'
    echo '| |  | |_| | |  __/\__ \  __/ |_  |  _|  __/ || (__| | | |  __/ |'
    echo '|_|   \__,_|_|\___||___/\___|\__| |_|  \___|\__\___|_| |_|\___|_|'
    echo -e "${NC}"
    printf '%*s' "$ver_pad" ''
    echo -e "${BLUE}${ver_text}${NC}"
    echo ""
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
