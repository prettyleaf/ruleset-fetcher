#!/bin/bash
# GitHub authentication: check, setup, token management

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
