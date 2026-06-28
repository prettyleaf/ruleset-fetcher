#!/bin/bash
# Cron job management

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
