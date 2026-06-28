#!/bin/bash
# Setup wizard and installation functions

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

setup_symlink() {
    if [[ "$EUID" -ne 0 ]]; then
        return 1
    fi

    local installed_script="${CONFIG_DIR}/ruleset-fetcher.sh"

    # Copy script + lib to config dir
    if [[ "$(readlink -f "$0")" != "$(readlink -f "${installed_script}" 2>/dev/null)" ]]; then
        mkdir -p "${CONFIG_DIR}"
        cp "$(readlink -f "$0")" "${installed_script}"
        chmod +x "${installed_script}"
        install_lib_files
    fi

    # Symlink /usr/local/bin/ruleset-fetcher → installed script
    if [[ -d "$(dirname "$SCRIPT_PATH")" ]]; then
        if [[ "$(readlink -f "${SCRIPT_PATH}" 2>/dev/null)" != "$(readlink -f "${installed_script}")" ]]; then
            rm -f "$SCRIPT_PATH"
            ln -s "${installed_script}" "${SCRIPT_PATH}"
        fi
    fi

    # Symlink rfetcher → ruleset-fetcher
    if [[ -d "$(dirname "$SYMLINK_PATH")" ]]; then
        if [[ "$(readlink -f "${SYMLINK_PATH}" 2>/dev/null)" != "$(readlink -f "${SCRIPT_PATH}" 2>/dev/null)" ]]; then
            rm -f "$SYMLINK_PATH"
            ln -s "$SCRIPT_PATH" "$SYMLINK_PATH" 2>/dev/null || true
        fi
    fi

    return 0
}

install_lib_files() {
    local source_dir="${SCRIPT_DIR}/lib"
    if [[ ! -d "${source_dir}" ]]; then
        source_dir="${LIB_DIR}"
    fi
    if [[ -d "${source_dir}" ]] && [[ "$(readlink -f "${source_dir}")" != "$(readlink -f "${CONFIG_DIR}/lib")" ]]; then
        mkdir -p "${CONFIG_DIR}/lib"
        cp "${source_dir}/"*.sh "${CONFIG_DIR}/lib/"
        chmod 644 "${CONFIG_DIR}/lib/"*.sh
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

run_setup() {
    [[ -t 0 && -z "${RF_NO_CLEAR:-}" ]] && clear
    echo ""
    print_banner
    echo "${MENU_LINE}"
    echo ""
    local setup_title="Setup Wizard"
    local setup_pad=$(( (MENU_WIDTH - ${#setup_title}) / 2 ))
    [[ $setup_pad -lt 0 ]] && setup_pad=0
    printf '%*s' "$setup_pad" ''
    echo -e "${BOLD}${setup_title}${NC}"
    local setup_sub="First-time configuration"
    local setup_sub_pad=$(( (MENU_WIDTH - ${#setup_sub}) / 2 ))
    [[ $setup_sub_pad -lt 0 ]] && setup_sub_pad=0
    printf '%*s' "$setup_sub_pad" ''
    echo -e "${LIGHT_GRAY}${setup_sub}${NC}"
    echo ""
    echo "${MENU_LINE}"
    echo ""
    check_root
    check_dependencies
    create_config_dir
    menu_footer
    read -rp "      Press Enter to start setup..."

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

    setup_symlink
    print_success "Script installed to ${SCRIPT_PATH}"
    install_cron_job "${UPDATE_INTERVAL}"

    echo ""
    echo "${MENU_LINE}"
    echo ""
    local done_title="Setup Complete"
    local done_pad=$(( (MENU_WIDTH - ${#done_title}) / 2 ))
    [[ $done_pad -lt 0 ]] && done_pad=0
    printf '%*s' "$done_pad" ''
    echo -e "${BOLD}${done_title}${NC}"
    echo ""
    echo "${MENU_LINE}"
    echo ""
    print_success "Configuration saved!"
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
