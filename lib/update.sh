#!/bin/bash
# Version checking and self-update

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

    local installed_script="${CONFIG_DIR}/ruleset-fetcher.sh"

    if [[ -f "${installed_script}.backup" ]]; then
        local backup_timestamp
        backup_timestamp=$(stat -c %Y "${installed_script}.backup" 2>/dev/null || stat -f %m "${installed_script}.backup" 2>/dev/null)

        if [[ -n "$backup_timestamp" && "$backup_timestamp" =~ ^[0-9]+$ ]]; then
            local backup_age_seconds=$(( $(date +%s) - backup_timestamp ))
            local one_day_seconds=$((24 * 60 * 60))

            if [[ $backup_age_seconds -gt $one_day_seconds ]]; then
                rm -f "${installed_script}.backup"
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

    local temp_lib_dir
    temp_lib_dir="$(mktemp -d -t ruleset-fetcher-lib.XXXXXX)" || {
        print_error "Failed to create temporary directory"
        rm -f "${temp_file}"
        return 1
    }

    local mod_download_ok=true
    for mod in "${RF_MODULES[@]}"; do
        local mod_url="https://raw.githubusercontent.com/${GITHUB_REPO}/${download_ref}/lib/${mod}.sh"
        if ! curl -fsSL --connect-timeout 30 --max-time 120 -o "${temp_lib_dir}/${mod}.sh" "${mod_url}" 2>/dev/null; then
            print_error "Failed to download module: ${mod}.sh"
            mod_download_ok=false
            break
        fi
    done

    if ! $mod_download_ok; then
        rm -f "${temp_file}"
        rm -rf "${temp_lib_dir}"
        return 1
    fi

    local had_backup=false
    if [[ -f "${installed_script}" ]]; then
        if [[ ! -r "${installed_script}" ]]; then
            print_error "Current script is not readable; aborting."
            rm -f "${temp_file}"
            rm -rf "${temp_lib_dir}"
            return 1
        fi
        if ! cp "${installed_script}" "${installed_script}.backup"; then
            print_error "Failed to create backup; aborting."
            rm -f "${temp_file}"
            rm -rf "${temp_lib_dir}"
            return 1
        fi
        had_backup=true
    fi

    mkdir -p "${CONFIG_DIR}"
    if ! mv "${temp_file}" "${installed_script}"; then
        print_error "Failed to install update"
        if [[ "${had_backup}" == true ]]; then
            if mv "${installed_script}.backup" "${installed_script}"; then
                print_info "Restored previous version from backup."
            else
                print_error "Failed to restore from backup at ${installed_script}.backup"
            fi
        fi
        rm -f "${temp_file}"
        rm -rf "${temp_lib_dir}"
        return 1
    fi

    if ! chmod +x "${installed_script}"; then
        print_error "Failed to make updated script executable"
        if [[ "${had_backup}" == true ]]; then
            if mv "${installed_script}.backup" "${installed_script}"; then
                print_info "Restored previous version from backup."
            else
                print_error "Failed to restore from backup at ${installed_script}.backup"
            fi
        fi
        rm -rf "${temp_lib_dir}"
        return 1
    fi

    mkdir -p "${CONFIG_DIR}/lib"
    cp "${temp_lib_dir}/"*.sh "${CONFIG_DIR}/lib/"
    chmod 644 "${CONFIG_DIR}/lib/"*.sh
    rm -rf "${temp_lib_dir}"

    setup_symlink

    print_success "Updated successfully to v${remote_version}!"
    echo ""
    if [[ -f "${installed_script}.backup" ]]; then
        print_info "Backup saved to: ${installed_script}.backup"
    fi
    log_message "INFO" "Updated from v${VERSION} to v${remote_version}"
}

show_version() {
    echo "ruleset-fetcher v${VERSION}"
    echo "https://github.com/${GITHUB_REPO}"
}
