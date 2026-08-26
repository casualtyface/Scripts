#!/usr/bin/env bash

# sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/casualtyface/Scripts/main/container-configuration-script/script.sh)"

set -euo pipefail

clear

# ─────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────
RESET='\033[0m'

MINT='\033[38;5;121m'
CYAN='\033[38;5;51m'
RED='\033[38;5;196m'

# ─────────────────────────────────────────────
# Colored printf helpers
# ─────────────────────────────────────────────
print_mint() {
    printf "${MINT}%s${RESET}\n" "$1"
}

print_value() {
    printf "${MINT}%s ${CYAN}%s${RESET}\n" "$1" "$2"
}

print_error() {
    printf "${RED}%s${RESET}\n" "$1"
}

print_mint_value() {
    printf "${MINT}%s${CYAN}%s${RESET}\n" "$1" "$2"
}

# ─────────────────────────────────────────────
# Required packages
# ─────────────────────────────────────────────
required=(
    bat
    git
    cmake
    make
    fish
    eza
    zoxide
    vim
    sudo
    fastfetch
    unattended-upgrades
)

pm=(
    apt
    dnf
    apk
    zypper
    yay
    pacman
    yum
)

pkg=()
missing=()
package_manager=()

print_mint_value "checking for packages: " "${required[*]}"

for cmd in "${required[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        pkg+=("$cmd")
    fi
done

for cmd in "${pm[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        package_manager+=("$cmd")
    fi
done

if (( ${#pkg[@]} > 0 )); then
    print_mint_value "Packages You dont have: " "${pkg[*]}"
    print_mint_value "Installing with " "${package_manager[0]} package manager"
else
    print_mint "packages already installed"
fi

# ─────────────────────────────────────────────
# Package repository check
# ─────────────────────────────────────────────
package_exists() {
    case "${package_manager[0]}" in
        apt)     apt-cache show "$1" >/dev/null 2>&1 ;;
        dnf)     dnf info "$1" >/dev/null 2>&1 ;;
        pacman)  pacman -Si "$1" >/dev/null 2>&1 ;;
        apk)     apk info "$1" >/dev/null 2>&1 ;;
        zypper)  zypper info "$1" >/dev/null 2>&1 ;;
        yum)     yum info "$1" >/dev/null 2>&1 ;;
        yay)     yay -Si "$1" >/dev/null 2>&1 ;;
    esac
}

for p in "${pkg[@]}"; do
    if package_exists "$p"; then
        print_mint_value "Package " "$p exists in repo"
    else
        missing+=("$p")
        print_mint_value "Package " "$p not found in repo"
    fi
done

invalid_pkg=("${missing[@]}")

filtered=()

for p in "${pkg[@]}"; do
    found=false

    for bad in "${invalid_pkg[@]}"; do
        if [[ $p == "$bad" ]]; then
            found=true
            break
        fi
    done

    $found || filtered+=("$p")
done

pkg=("${filtered[@]}")

# ─────────────────────────────────────────────
# Install packages
# ─────────────────────────────────────────────
case "${package_manager[0]}" in
    apt)
        apt-get update >/dev/null 2>&1
        apt-get install -y "${pkg[@]}" >/dev/null 2>&1
        ;;

    dnf)
        dnf check-update --refresh >/dev/null 2>&1
        dnf install -y "${pkg[@]}" >/dev/null 2>&1
        ;;

    apk)
        apk update >/dev/null 2>&1
        apk add "${pkg[@]}"
        ;;

    zypper)
        zypper refresh >/dev/null 2>&1
        zypper install -y --no-confirm "${pkg[@]}" >/dev/null 2>&1
        ;;

    yay)
        yay -Sy --needed --noconfirm "${pkg[@]}" >/dev/null 2>&1
        ;;

    pacman)
        pacman -Sy --needed --noconfirm "${pkg[@]}" >/dev/null 2>&1
        ;;

    yum)
        yum check-update >/dev/null 2>&1
        yum install -y "${pkg[@]}" >/dev/null 2>&1
        ;;

    *)
        print_error "Unsupported package manager."
        exit 1
        ;;
esac

# ─────────────────────────────────────────────
# Install fastfetch
# ─────────────────────────────────────────────
install_fastfetch() {
    cleanup() {
        rm -rf "$build_dir"
    }

    build_dir=$(mktemp -d)

    print_mint "fastfetch is missing"
    print_mint "Cloning fastfetch..."

    git clone --depth=1 \
        https://github.com/fastfetch-cli/fastfetch.git \
        "$build_dir" || {
            print_error "ERROR: Failed to clone fastfetch"
            cleanup
            return 1
        }

    pushd "$build_dir" >/dev/null || {
        print_error "ERROR: Failed to enter fastfetch build directory"
        cleanup
        return 1
    }

    print_mint "Building fastfetch..."

    cmake -B build -DCMAKE_BUILD_TYPE=Release || {
        popd >/dev/null
        cleanup
        return 1
    }

    cmake --build build -j"$(nproc)" || {
        popd >/dev/null
        cleanup
        return 1
    }

    print_mint "Installing fastfetch..."

    sudo cmake --install build || {
        popd >/dev/null
        cleanup
        return 1
    }

    popd >/dev/null
    cleanup

    print_mint "fastfetch installed successfully"
}



install_fastfetch

# ─────────────────────────────────────────────
# Install personal scripts
# ─────────────────────────────────────────────
install_my_scripts() {

    cleanup() {
    [[ -n "${build_dir:-}" && -d "$build_dir" ]] && rm -rf "$build_dir"
    }

    build_dir=$(mktemp -d)


    repo="https://github.com/casualtyface/Scripts.git"
    fish_config="$build_dir/container-configuration-script/fish/config.fish"

    print_mint "Cloning Scripts repo..."

    git clone --depth=1 "$repo" "$build_dir" || {
        print_error "ERROR: Failed to clone Scripts repository"
        cleanup
        return 1
    }

    if [[ ! -f "$fish_config" ]]; then
        print_error "ERROR: config.fish not found in repository"
        cleanup
        return 1
    fi

    while IFS=: read -r username _ uid _ _ home _; do

        # Skip users without a real home directory
        [[ "$home" == /home/* && -d "$home" ]] || continue

        local_config="$home/.config/fish/config.fish"

        mkdir -p "$home/.config/fish" || {
            print_error "ERROR: Failed to create Fish config directory for $username"
            continue
        }

        if [[ ! -f "$local_config" ]] ||
           ! cmp -s "$fish_config" "$local_config"; then

            print_mint_value "Installing Fish config for " "$username..."

            cp "$fish_config" "$local_config" || {
                print_error "ERROR: Failed to install Fish config for $username"
                continue
            }

            chown "$username:$username" "$local_config"

        else
            print_mint_value "Fish config for " "$username is already up to date"
        fi

    done < /etc/passwd

    cleanup
}

install_my_scripts

# ─────────────────────────────────────────────
# SSH / MOTD configuration
# ─────────────────────────────────────────────
[[ ! -d "$HOME/.ssh" ]] && {
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
}

[[ -e /etc/update-motd.d/10-uname ]] &&
    sudo rm -f /etc/update-motd.d/10-uname

[[ -d /etc/update-motd.d ]] &&
    sudo chmod -x /etc/update-motd.d/*

[[ ! -e /root/.hushlogin ]] &&
    sudo touch /root/.hushlogin

config="/etc/ssh/sshd_config"
backup="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

if [[ ! -e "$backup" ]]; then
    if cp "$config" "$backup"; then
        print_mint_value "Backup created: " "$backup"
    else
        print_error "ERROR: Backup failed"
    fi
fi

declare -A settings=(
    ["AddressFamily"]="inet"
    ["PermitRootLogin"]="prohibit-password"
    ["PasswordAuthentication"]="no"
    ["PrintMotd"]="no"
    ["PrintLastLog"]="no"
    ["Banner"]="none"
)

for key in "${!settings[@]}"; do
    value="${settings[$key]}"

    if grep -qE "^[#[:space:]]*$key[[:space:]]+" "$config"; then

        sed -i -E \
            "s|^[#[:space:]]*$key[[:space:]].*|$key $value|" \
            "$config"

    else
        printf "%s\n" "$key $value" >> "$config"
    fi
done

print_mint "SSH configuration updated."

if sshd -t; then
    print_mint "SSH configuration syntax OK."
else
    print_error "ERROR: SSH configuration test failed."
    print_mint_value "Restore backup: " "cp \"$backup\" \"$config\""
fi

# ─────────────────────────────────────────────
# PAM configuration
# ─────────────────────────────────────────────
config="/etc/pam.d/sshd"

if [[ -f "$config" ]]; then

    backup="${config}.backup.$(date +%Y%m%d_%H%M%S)"

    if cp "$config" "$backup"; then
        print_mint_value "Backup created: " "$backup"
    else
        print_error "ERROR: Failed to create backup of $config"
        exit 1
    fi

    RULES=(
        "session    optional     pam_motd.so  motd=/run/motd.dynamic"
        "session    optional     pam_motd.so noupdate"
        "session    optional     pam_mail.so standard noenv"
    )

    for rule in "${RULES[@]}"; do

        if grep -qF "$rule" "$config"; then

            sed -i "s|^$rule|#$rule|" "$config"

            print_mint_value "Disabled: " "$rule"

        else
            print_mint_value "Not found: " "$rule"
        fi

    done

    print_mint "Current PAM entries:"
    grep -E "pam_motd|pam_mail" "$config"

else
    print_error "$config not found. Skipping PAM configuration."
fi

# ─────────────────────────────────────────────
# Restart SSH
# ─────────────────────────────────────────────
if systemctl restart sshd >/dev/null 2>&1; then

    print_mint "SSH service restarted successfully."
    systemctl status sshd --no-pager

elif systemctl restart ssh >/dev/null 2>&1; then

    print_mint "SSH service restarted successfully."
    systemctl status ssh --no-pager

else

    print_error "ERROR: Failed to restart SSH service."
    print_mint "Checking SSH configuration:"
    sshd -t

fi

# ─────────────────────────────────────────────
# Add fish to valid login shells
# ─────────────────────────────────────────────
if ! grep -qx "/usr/local/bin/fish" /etc/shells; then
    print_mint_value "Adding valid shell: " "/usr/local/bin/fish"

    printf "%s\n" "/usr/local/bin/fish" |
        sudo tee -a /etc/shells >/dev/null
fi

# ─────────────────────────────────────────────
# Change current user's shell to fish
# ─────────────────────────────────────────────
fish_path="$(command -v fish)"

print_mint_value "Changing login shell to: " "$fish_path"

chsh -s "$fish_path"
