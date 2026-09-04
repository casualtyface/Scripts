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

print_error() {
    printf "${RED}%s${RESET}\n" "$1"
}

print_mint_value() {
    printf "${MINT}%s${CYAN}%s${RESET}\n" "$1" "$2"
}

print_red_value() {
    printf "${RED}%s${CYAN}%s${RESET}\n" "$1" "$2"
}

print_mint_value_mint() {
    printf "${MINT}%s${CYAN}%s${MINT}%s${RESET}\n" "$1" "$2" "$3"
}

print_mint_value_red() {
    printf "${MINT}%s${CYAN}%s${RED}%s${RESET}\n" "$1" "$2" "$3"
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
    software-properties-common

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

repositories=(
    "universe"
    "ppa:zhangsongcui3371/fastfetch"
)

pkg=()
missing=()
package_manager=()

print_mint_value "checking for packages: " "${required[*]}"

add_repositories() {
    for repo in "${repositories[@]}"; do
        if grep -Rqs "$repo" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
            print_mint_value "Repository already exists: " "$repo"
            continue
        fi

        print_mint_value "Adding repository: " "$repo"
        sudo add-apt-repository -y "$repo"
    done

    sudo apt-get update >/dev/null 2>&1
}


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
        print_mint_value_mint "Package " "$p " "exists in repo"
    else
        missing+=("$p")
        print_mint_value_red "Package " "$p " "not found in repo"
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
print_mint_value_mint "Installing with " "${package_manager[0]} " "package manager"
case "${package_manager[0]}" in
    apt)
        apt-get update
        print_mint_value "Installing: " "${pkg[*]}"
        apt-get install -y "${pkg[@]}"
        ;;

    dnf)
        dnf check-update --refresh >/dev/null 2>&1
        print_mint_value "Installing: " "${pkg[*]}"
        dnf install -y "${pkg[@]}" >/dev/null 2>&1
        ;;

    apk)
        apk update >/dev/null 2>&1
        print_mint_value "Installing: " "${pkg[*]}"
        apk add "${pkg[@]}"
        ;;

    zypper)
        zypper refresh >/dev/null 2>&1
        print_mint_value "Installing: " "${pkg[*]}"
        zypper install -y --no-confirm "${pkg[@]}" >/dev/null 2>&1
        ;;

    yay)
        print_mint_value "Installing: " "${pkg[*]}"
        yay -Sy --needed --noconfirm "${pkg[@]}" >/dev/null 2>&1
        ;;

    pacman)
        print_mint_value "Installing: " "${pkg[*]}"
        pacman -Sy --needed --noconfirm "${pkg[@]}" >/dev/null 2>&1
        ;;

    yum)
        yum check-update >/dev/null 2>&1
        print_mint_value "Installing: " "${pkg[*]}"
        yum install -y "${pkg[@]}" >/dev/null 2>&1
        ;;

    *)
        print_error "Unsupported package manager."
        exit 1
        ;;
esac

add_repositories

# ─────────────────────────────────────────────
# Install fastfetch
# ─────────────────────────────────────────────
install_fastfetch() {

    FASTFETCH_VERSION="2.67.0"

    cleanup() {
        [[ -n "${build_dir:-}" && -d "$build_dir" ]] && rm -rf "$build_dir"
    }

    if command -v fastfetch >/dev/null 2>&1; then
        print_mint "fastfetch is already installed"
        return 0
    fi

    # ─────────────────────────────────────────
    # Try package manager first
    # ─────────────────────────────────────────
    if [[ "${package_manager[0]}" == "apt" ]]; then

        if apt-cache show fastfetch >/dev/null 2>&1; then
            print_mint "fastfetch is available through apt"
            print_mint "Installing fastfetch with apt..."

            sudo apt-get install -y fastfetch >/dev/null 2>&1 || {
                print_error "ERROR: Failed to install fastfetch with apt"
                return 1
            }

            print_mint "fastfetch installed successfully"
            return 0
        fi

        print_mint "fastfetch is not available through apt"
        print_mint "Proceeding with source build..."

    fi

    # ─────────────────────────────────────────
    # Build fastfetch from source
    # ─────────────────────────────────────────

    print_mint "fastfetch is missing"

    build_dir=$(mktemp -d) || {
        print_error "ERROR: Failed to create temporary build directory"
        return 1
    }

    print_mint "Cloning fastfetch..."

    curl -fL --retry 3 \
        "https://github.com/fastfetch-cli/fastfetch/archive/refs/tags/${FASTFETCH_VERSION}.tar.gz" \
        -o "$build_dir/fastfetch.tar.gz" >/dev/null || {
            print_error "ERROR: Failed to download fastfetch"
            cleanup
            return 1
        }

    tar -xzf "$build_dir/fastfetch.tar.gz" -C "$build_dir" || {
        print_error "ERROR: Failed to extract fastfetch"
        cleanup
        return 1
    }

    mv "$build_dir/fastfetch-${FASTFETCH_VERSION}" "$build_dir/source" || {
        print_error "ERROR: Failed to prepare fastfetch source"
        cleanup
        return 1
    }

    pushd "$build_dir/source" >/dev/null || {
        print_error "ERROR: Failed to enter fastfetch build directory"
        cleanup
        return 1
    }

    print_mint "Building fastfetch..."

    cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1 || {
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

    sudo cmake --install build >/dev/null 2>&1 || {
        popd >/dev/null
        cleanup
        return 1
    }

    popd >/dev/null
    cleanup

    print_mint "fastfetch installed successfully"
}

# ─────────────────────────────────────────────
# Install bat
# ─────────────────────────────────────────────
install_bat() {

    if command -v bat >/dev/null 2>&1; then
        print_mint "bat is already installed"
        return 0
    fi

    print_mint "bat is missing"

    # ─────────────────────────────────────────
    # Try package manager
    # ─────────────────────────────────────────
    if [[ "${package_manager[0]}" == "apt" ]]; then

        if apt-cache show bat >/dev/null 2>&1; then
            print_mint "bat is available through apt"
            print_mint "Installing bat with apt..."

            sudo apt-get install -y bat >/dev/null 2>&1 || {
                print_error "ERROR: Failed to install bat with apt"
                return 1
            }

            print_mint "bat installed successfully"
            return 0
        fi

        print_red_value "ERROR: bat is not available through " "apt"
        return 1
    fi

    print_red_value "ERROR: bat cannot be installed automatically with " "${package_manager[0]}"
    return 1
}

install_fastfetch
install_bat

# ─────────────────────────────────────────────
# Install personal scripts
# ─────────────────────────────────────────────
install_my_scripts() {

    # source path | destination path | display name
    local configs=(
        "fish/config.fish|.config/fish/config.fish|Fish"
        "bat/config|.config/bat/config|bat"
    )

    cleanup() {
        [[ -n "${build_dir:-}" && -d "$build_dir" ]] && rm -rf "$build_dir"
    }

    build_dir=$(mktemp -d) || {
        print_error "ERROR: Failed to create temporary directory"
        return 1
    }

    local config_dir="$build_dir/container-configuration-script"

    print_mint "Downloading configuration scripts..."

    curl -fL --retry 3 \
        "https://github.com/casualtyface/Scripts/archive/refs/heads/main.tar.gz" |
        tar -xz -C "$build_dir" || {
            print_error "ERROR: Failed to download configuration scripts"
            cleanup
            return 1
        }

    local config_dir="$build_dir/Scripts-main/container-configuration-script"

    while IFS=: read -r username _ _ _ _ home _; do

        # Skip users without a real home directory
        [[ "$home" == "/root" || "$home" == /home/* ]] &&
        [[ -d "$home" ]] ||
        continue

        for config in "${configs[@]}"; do

            IFS='|' read -r source destination name <<< "$config"

            source="$config_dir/$source"
            destination="$home/$destination"
            destination_dir="$(dirname "$destination")"

            mkdir -p "$destination_dir" || {
                print_error "ERROR: Failed to create config directory for $username: $destination_dir"
                continue
            }

            chown "$username:$username" "$destination_dir" || {
                print_error "ERROR: Failed to set ownership of config directory for $username"
                continue
            }

            if [[ ! -f "$destination" ]] ||
               ! cmp -s "$source" "$destination"; then

                print_mint_value "Installing $name config for " "$username..."

                cp "$source" "$destination" || {
                    print_error "ERROR: Failed to install $name config for $username"
                    continue
                }

                chown "$username:$username" "$destination" || {
                    print_error "ERROR: Failed to set ownership of $name config for $username"
                    continue
                }

            else
                print_mint_value "$name config for " "$username is already up to date"
            fi

        done

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
