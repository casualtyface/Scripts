#!/usr/bin/env bash
set -euo pipefail

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

if [[ -n ${pkg[@]} ]]; then
    printf "%s\n" "Packages You dont have: ${pkg[*]}"
    printf "%s\n" "Installing with ${package_manager[$1]} package manager"
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
    ! package_exists "$p" && missing+=("$p") || echo "Skipping $p"
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

pkg=("${filtered[*]}")

case "$package_manager" in
    apt)
        apt-get update
        apt-get install -y "${pkg[@]}"
        ;;
    dnf)
        dnf check-update --refresh
        dnf install -y "${pkg[@]}"
        ;;
    apk)
        apk update
        apk add "${pkg[@]}"
        ;;
    zypper)
        zypper refresh
        zypper install -y --no-confirm "${pkg[@]}"
        ;;
    yay)
        yay -Sy --needed --noconfirm "${pkg[@]}"
        ;;
    pacman)
        pacman -Sy --needed --noconfirm "${pkg[@]}"
        ;;
    yum)
        yum check-update
        yum install -y "${pkg[@]}"
        ;;
    *)
        printf "%s\n" "Unsupported package manager."
        exit 1
        ;;
esac

install_fastfetch() {
    if command -v fastfetch >/dev/null 2>&1; then
        printf "%s\n" "fastfetch already installed"
        return
    fi

    if command -v apt >/dev/null 2>&1; then
        # Try distro package first
        if apt-cache show fastfetch >/dev/null 2>&1; then
            sudo apt install -y fastfetch
            return
        fi

        printf "%s\n" "fastfetch not found in apt, downloading .deb..."

        ARCH=$(dpkg --print-architecture)

        case "$ARCH" in
            amd64)
                FILE="fastfetch-linux-amd64.deb"
                ;;
            arm64)
                FILE="fastfetch-linux-aarch64.deb"
                ;;
            *)
                printf "%s\n" "Unsupported architecture: $ARCH"
                exit 1
                ;;
        esac

        URL=$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
            | grep browser_download_url \
            | grep "$FILE" \
            | cut -d '"' -f 4)

        wget -q "$URL" -O "/tmp/$FILE"

        sudo dpkg -i "/tmp/$FILE" || sudo apt -f install -y

        rm -f "/tmp/$FILE"

    else
        printf "%s\n" "No supported package manager found"
        exit 1
    fi
}

install_fastfetch

printf "%s\n" "Cloning Repo"

REPO="https://github.com/casualtyface/Scripts.git"
DOTFILES="$HOME/.dotfiles"

git clone "$REPO" "$DOTFILES"

mkdir -p "$HOME/.config/fish"

ln -sf "$DOTFILES/fish/config.fish" "$HOME/.config/fish/config.fish"

chmod 644 "$HOME/.config/fish/config.fish"

if [ ! -d "$HOME/.ssh" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
fi

# Disable the default MOTD scripts (Debian/Ubuntu)
sudo rm -f /etc/update-motd.d/10-uname

if [ -d /etc/update-motd.d ]; then
    sudo chmod -x /etc/update-motd.d/*
fi

# Silence the login banner for root
sudo touch /root/.hushlogin

CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

# Create backup
cp "$CONFIG" "$BACKUP"

printf "%s\n" "Backup created: $BACKUP"

declare -A SETTINGS=(
    ["AddressFamily"]="inet"
    ["PermitRootLogin"]="prohibit-password"
    ["PasswordAuthentication"]="no"
    ["PrintMotd"]="no"
    ["PrintLastLog"]="no"
    ["Banner"]="none"
)

for key in "${!SETTINGS[@]}"; do
    value="${SETTINGS[$key]}"

    if grep -qE "^[#[:space:]]*$key[[:space:]]+" "$CONFIG"; then
        # Replace existing entry
        sed -i -E "s|^[#[:space:]]*$key[[:space:]].*|$key $value|" "$CONFIG"
    else
        # Add missing entry
        printf "%s\n" "$key $value" >> "$CONFIG"
    fi
done

printf "%s\n" "SSH configuration updated."

# Check configuration
sshd -t

if [ $? -eq 0 ]; then
    printf "%s\n" "SSH configuration syntax OK."
    printf "%s\n" "Restart SSH service to apply changes:"
    printf "%s\n" "systemctl restart sshd"
else
    printf "%s\n" "ERROR: SSH configuration test failed. Restore backup:"
    printf "%s\n" "cp $BACKUP $CONFIG"
fi

CONFIG="/etc/pam.d/sshd"

if [ ! -f "$CONFIG" ]; then
    printf "%s\n" "ERROR: Cannot find $CONFIG"
    exit 1
fi

BACKUP="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

cp "$CONFIG" "$BACKUP"

printf "%s\n" "Backup created: $BACKUP"

RULES=(
"session    optional     pam_motd.so  motd=/run/motd.dynamic"
"session    optional     pam_motd.so noupdate"
"session    optional     pam_mail.so standard noenv"
)

for rule in "${RULES[@]}"; do
    if grep -qF "$rule" "$CONFIG"; then
        sed -i "s|^$rule|#$rule|" "$CONFIG"
        printf "%s\n" "Disabled: $rule"
    else
        printf "%s\n" "Not found: $rule"
    fi
done

printf "%s\n"
printf "%s\n" "Current PAM entries:"
grep -E "pam_motd|pam_mail" "$CONFIG"

systemctl restart sshd

if [ $? -eq 0 ]; then
    printf "%s\n" "SSH service restarted successfully."
    systemctl status sshd --no-pager
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

