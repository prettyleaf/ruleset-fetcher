#!/bin/bash
# File download functions

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
