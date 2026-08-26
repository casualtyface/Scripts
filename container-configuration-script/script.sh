#!/usr/bin/env bash

# bash -c "$(curl -fsSL https://raw.githubusercontent.com/casualtyface/Scripts/main/container-configuration-script/script.sh)"
set -euo pipefail

clear

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

package_manager=()

printf "%s\n" "checking for packages: ${required[*]}"

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

if [[ -n ${pkg[*]} ]]; then
    printf "%s\n" "Packages You dont have: ${pkg[*]}"
    printf "%s\n" "Installing with ${package_manager[*]} package manager"
else
    printf "%s\n" "packages already installed"
fi

package_exists() {
    case "$package_manager" in
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
    package_exists "$p" && echo "Skipping $p" || missing+=("$p")
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

case "$package_manager" in
    apt)
        apt-get update
        apt-get install -y "${pkg[@]}" >/dev/null 2>&1
        ;;
    dnf)
        dnf check-update --refresh
        dnf install -y "${pkg[@]}" >/dev/null 2>&1
        ;;
    apk)
        apk update
        apk add "${pkg[@]}"
        ;;
    zypper)
        zypper refresh
        zypper install -y --no-confirm "${pkg[@]}" >/dev/null 2>&1
        ;;
    yay)
        yay -Sy --needed --noconfirm "${pkg[@]}" >/dev/null 2>&1
        ;;
    pacman)
        pacman -Sy --needed --noconfirm "${pkg[@]}" >/dev/null 2>&1
        ;;
    yum)
        yum check-update
        yum install -y "${pkg[@]}" >/dev/null 2>&1
        ;;
    *)
        printf "%s\n" "Unsupported package manager."
        exit 1
        ;;
esac

install_fastfetch() {
    if command -v fastfetch >/dev/null 2>&1; then
        printf "%s\n" "fastfetch is already installed"
        return
    fi

    cleanup() { rm -rf "$build_dir"; }
    build_dir=$(mktemp -d)

    printf "%s\n" "fastfetch is missing"
    printf "%s\n" "Cloning fastfetch..."

    git clone --depth=1 https://github.com/fastfetch-cli/fastfetch.git "$build_dir" || {
        cleanup
        return 1
    }
               
    cd "$build_dir" || {
        cleanup
        return 1
    }

    printf "%s\n" "Building fastfetch..."

    cmake -B build -DCMAKE_BUILD_TYPE=Release || {
        cleanup
        return 1
    }

    cmake --build build -j"$(nproc)" || {
        cleanup
        return 1
    }

    printf "%s\n" "Installing fastfetch..."

    sudo cmake --install build || {
        cleanup
        return 1
    }

    cleanup

    printf "%s\n" "fastfetch installed successfully"
}

install_fastfetch

install_my_scripts() {
    cleanup() { rm -rf "$build_dir"; }
    build_dir=$(mktemp -d)
    repo="https://github.com/casualtyface/Scripts.git"
    fish_config="$build_dir/container-configuration-script/fish/config.fish"
    local_config="$HOME/.config/fish/config.fish"
    repo_exist="$build_dir/container-configuration-script"

    # Clone the repo if it doesn't exist
    if [[ ! -d "$repo_exist" ]]; then
        printf "%s\n" "Cloning Scripts repo..."
        git clone --depth=1 "$repo" "$build_dir" || cleanup return 1
    else
        printf "%s\n" "Scripts repo exists"
    fi

    mkdir -p "$HOME/.config/fish"

    # Install if missing or different from the repo version
    if [[ ! -f "$local_config" ]] || \
       [[ "$(sha256sum "$fish_config" | awk '{print $1}')" != "$(sha256sum "$local_config" | awk '{print $1}')" ]]; then

        printf "%s\n" "Installing/updating fish config..."

        chmod 644 "$fish_config"
        cp "$fish_config" "$local_config"
    else
        printf "%s\n" "Fish config is already up to date"
    fi
    cleanup
}

install_my_scripts

[[ ! -d "$HOME/.ssh" ]] && { mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; }

[[ -e /etc/update-motd.d/10-uname ]] && sudo rm -f /etc/update-motd.d/10-uname

[[ -d /etc/update-motd.d ]] && sudo chmod -x /etc/update-motd.d/*

[[ ! -e /root/.hushlogin ]] && sudo touch /root/.hushlogin

config="/etc/ssh/sshd_config"
backup="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

[[ ! -e "$backup" ]] && cp "$config" "$backup" && printf "%s\n" "Backup created: $backup" || printf "%s\n" "Backup failed"

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
        # Replace existing entry
        sed -i -E "s|^[#[:space:]]*$key[[:space:]].*|$key $value|" "$config"
    else
        # Add missing entry
        printf "%s\n" "$key $value" >> "$config"
    fi
done

printf "%s\n" "SSH configuration updated."

if sshd -t; then
    printf "%s\n" "SSH configuration syntax OK."
else
    printf "%s\n" "ERROR: SSH configuration test failed. Restore backup:"
    printf "%s\n" "cp \"$backup\" \"$config\""
fi

config="/etc/pam.d/sshd"

if [[ -f "$config" ]]; then
    backup="${config}.backup.$(date +%Y%m%d_%H%M%S)"

    if cp "$config" "$backup"; then
        printf "%s\n" "Backup created: $backup"
    else
        printf "%s\n" "ERROR: Failed to create backup of $config"
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
            printf "%s\n" "Disabled: $rule"
        else
            printf "%s\n" "Not found: $rule"
        fi
    done

    printf "%s\n" "Current PAM entries:"
    grep -E "pam_motd|pam_mail" "$config"
else
    printf "%s\n" "$config not found. Skipping PAM configuration."
fi

if systemctl restart sshd >/dev/null 2>&1; then
    printf "%s\n" "SSH service restarted successfully."
    systemctl status sshd --no-pager
elif systemctl restart ssh >/dev/null 2>&1; then
    printf "%s\n" "SSH service restarted successfully."
    systemctl status ssh --no-pager
else
    printf "%s\n" "ERROR: Failed to restart SSH service."
    printf "%s\n" "Checking SSH configuration:"
    sshd -t
fi


# Add fish to valid login shells if not already present
if ! grep -qx "/usr/local/bin/fish" /etc/shells; then
    printf "%s\n" "/usr/local/bin/fish" | sudo tee -a /etc/shells >/dev/null
fi

# Change current user's shell to fish
chsh -s "$(command -v fish)"

