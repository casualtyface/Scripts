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

run_as_root() {
        if [[ $EUID -eq 0 ]]; then
            "$@"
        elif command -v sudo >/dev/null 2>&1; then
            sudo "$@"
        elif command -v doas >/dev/null 2>&1; then
            doas "$@"
        else
            print_error "ERROR: Root privileges are required."
            return 1
        fi
}

run_as_root

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
        apt-get update >/dev/null 2>&1
        print_mint_value "Installing: " "${pkg[*]}"
        apt-get install -y "${pkg[@]}" >/dev/null 2>&1
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

# ─────────────────────────────────────────────
# Install fastfetch
# ─────────────────────────────────────────────
install_fastfetch() {
    local pkg_manager=""
    local installer=""
    local build_dir=""
    local arch=""
    local url=""

    print_mint "fastfetch is missing"
    print_mint "Trying to install fastfetch..."

    # ------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------

    cleanup() {
        [[ -n "${build_dir:-}" && -d "$build_dir" ]] && rm -rf "$build_dir"
    }

    run_as_root() {
        if [[ $EUID -eq 0 ]]; then
            "$@"
        elif command -v sudo >/dev/null 2>&1; then
            sudo "$@"
        elif command -v doas >/dev/null 2>&1; then
            doas "$@"
        else
            print_error "ERROR: Root privileges are required."
            return 1
        fi
    }

    command_exists() {
        command -v "$1" >/dev/null 2>&1
    }

    verify_fastfetch() {
        if command_exists fastfetch; then
            print_mint "fastfetch installed successfully"
            return 0
        fi

        print_error "ERROR: fastfetch installation completed, but the binary was not found."
        return 1
    }

    # ------------------------------------------------------------
    # Package manager detection
    # ------------------------------------------------------------

    if command_exists pacman; then
        pkg_manager="pacman"
        installer=(pacman -S --needed --noconfirm fastfetch)

    elif command_exists dnf; then
        pkg_manager="dnf"
        installer=(dnf install -y fastfetch)

    elif command_exists zypper; then
        pkg_manager="zypper"
        installer=(zypper --non-interactive install fastfetch)

    elif command_exists apk; then
        pkg_manager="apk"
        installer=(apk add --no-cache fastfetch)

    elif command_exists xbps-install; then
        pkg_manager="xbps"
        installer=(xbps-install -Sy fastfetch)

    elif command_exists emerge; then
        pkg_manager="emerge"
        installer=(emerge --ask=n app-misc/fastfetch)

    elif command_exists eopkg; then
        pkg_manager="eopkg"
        installer=(eopkg install -y fastfetch)

    elif command_exists nix-env; then
        pkg_manager="nix"
        installer=(nix-env -iA nixpkgs.fastfetch)

    elif command_exists brew; then
        pkg_manager="brew"
        installer=(brew install fastfetch)

    elif command_exists apt-get; then
        pkg_manager="apt"
        installer=(apt-get install -y fastfetch)

    elif command_exists apt; then
        pkg_manager="apt"
        installer=(apt install -y fastfetch)
    fi

    # ------------------------------------------------------------
    # Package manager installation
    # ------------------------------------------------------------

    if [[ -n "$pkg_manager" ]]; then
        print_mint_value "Detected package manager: " "$pkg_manager"

        case "$pkg_manager" in
            pacman)
                run_as_root "${installer[@]}"
                ;;

            dnf|zypper|apk|xbps|emerge|eopkg|apt)
                run_as_root "${installer[@]}"
                ;;

            nix)
                "${installer[@]}"
                ;;

            brew)
                "${installer[@]}"
                ;;
        esac

        if verify_fastfetch; then
            return 0
        fi

        print_error "Package manager could not provide fastfetch."
        print_mint "Falling back to official binary..."
    fi

    # ------------------------------------------------------------
    # Homebrew fallback
    # ------------------------------------------------------------

    if command_exists brew; then
        print_mint "Installing fastfetch with Homebrew..."

        if brew install fastfetch; then
            verify_fastfetch && return 0
        fi
    fi

    # ------------------------------------------------------------
    # Official binary fallback
    #
    # Fastfetch publishes Linux binaries for x86_64 and aarch64.
    # ------------------------------------------------------------

    if ! command_exists curl && ! command_exists wget; then
        print_error "ERROR: curl or wget is required for the binary fallback."
        return 1
    fi

    arch="$(uname -m)"

    case "$arch" in
        x86_64|amd64)
            arch="amd64"
            ;;

        aarch64|arm64)
            arch="aarch64"
            ;;

        *)
            print_error "ERROR: Unsupported CPU architecture: $arch"
            print_error "Try installing fastfetch manually through your distro."
            return 1
            ;;
    esac

    build_dir="$(mktemp -d)"

    print_mint "Downloading official fastfetch binary..."

    # Get the latest release information from GitHub.
    local release_api="https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest"
    local release_json="$build_dir/release.json"

    if command_exists curl; then
        curl -fsSL "$release_api" -o "$release_json" || {
            print_error "ERROR: Failed to retrieve fastfetch release information."
            cleanup
            return 1
        }
    else
        wget -qO "$release_json" "$release_api" || {
            print_error "ERROR: Failed to retrieve fastfetch release information."
            cleanup
            return 1
        }
    fi

    # Find the Linux tarball for the current architecture.
    url="$(
        grep -oE '"browser_download_url":[[:space:]]*"[^"]+fastfetch-linux-'"$arch"'[^"]+\.tar\.gz"' \
            "$release_json" |
        sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]+)".*/\1/' |
        head -n1
    )"

    if [[ -z "$url" ]]; then
        print_error "ERROR: Could not find an official fastfetch binary for $arch."
        cleanup
        return 1
    fi

    print_mint_value "Downloading: " "$url"

    if command_exists curl; then
        curl -fL "$url" -o "$build_dir/fastfetch.tar.gz" || {
            print_error "ERROR: Failed to download fastfetch."
            cleanup
            return 1
        }
    else
        wget -q "$url" -O "$build_dir/fastfetch.tar.gz" || {
            print_error "ERROR: Failed to download fastfetch."
            cleanup
            return 1
        }
    fi

    print_mint "Installing official binary..."

    tar -xzf "$build_dir/fastfetch.tar.gz" -C "$build_dir" || {
        print_error "ERROR: Failed to extract fastfetch."
        cleanup
        return 1
    }

    local fastfetch_bin
    fastfetch_bin="$(find "$build_dir" -type f -name fastfetch -perm -111 | head -n1)"

    if [[ -z "$fastfetch_bin" ]]; then
        print_error "ERROR: fastfetch binary was not found in the archive."
        cleanup
        return 1
    fi

    run_as_root install -Dm755 "$fastfetch_bin" /usr/local/bin/fastfetch || {
        print_error "ERROR: Failed to install fastfetch to /usr/local/bin."
        cleanup
        return 1
    }

    cleanup

    verify_fastfetch
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

    git clone --depth=1 "$repo" "$build_dir" >/dev/null 2>&1 || {
        print_error "ERROR: Failed to clone Scripts repository"
        cleanup
        return 1
    }
``
    if [[ ! -f "$fish_config" ]]; then
        print_error "ERROR: config.fish not found in repository"
        cleanup
        return 1
    fi

    while IFS=: read -r username _ _ _ _ home _; do

        # Skip users without a real home directory
        [[ "$home" == "/root" || "$home" == /home/* ]] &&
        [[ -d "$home" ]] ||
        continue

        local_config="$home/.config/fish/config.fish"

        mkdir -p "$home/.config/fish" || {
            print_error "ERROR: Failed to create Fish config directory for $username"
            continue
        }

        chown "$username:$username" "$home/.config" "$home/.config/fish" || {
        print_error "ERROR: Failed to set ownership of Fish config directory for $username"
        continue
        }

        if [[ ! -f "$local_config" ]] ||
           ! cmp -s "$fish_config" "$local_config"; then

            print_mint_value "Installing Fish config for " "$username..."

            cp "$fish_config" "$local_config" || {
                print_error "ERROR: Failed to install Fish config for $username"
                continue
            }

            if ! chown "$username:$username" "$local_config"; then
                print_error "ERROR: Failed to set ownership for $username"
            continue
fi

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
