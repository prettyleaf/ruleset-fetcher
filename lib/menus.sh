#!/bin/bash
# Interactive menu functions

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
