#!/bin/bash
# Telegram notification functions

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
