#!/usr/bin/env bash
set -euo pipefail

pkg=(
    bat
    git
    fish
    eza
    zoxide
    vim
    sudo
)
extra_pkg=(
    fastfetch
)
deb_pkg=(
    unattended-upgrades
)

install_packages() {
    if command -v apt >/dev/null 2>&1; then
        apt-get update
        apt-get install -y "${pkg[@]}" "${deb_pkg[@]}"

    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "${pkg[@]}" "${extra_pkg[@]}"

    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --needed "${pkg[@]}" "${extra_pkg[@]}"

    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y "${pkg[@]}" "${extra_pkg[@]}"

    elif command -v apk >/dev/null 2>&1; then
        apk add "${pkg[@]}" "${extra_pkg[@]}"

    elif command -v brew >/dev/null 2>&1; then
        install "${pkg[@]}" "${extra_pkg[@]}"

    else
        echo "Unsupported package manager."
        exit 1
    fi
}

install_packages

install_fastfetch() {
    if command -v fastfetch >/dev/null 2>&1; then
        echo "fastfetch already installed"
        return
    fi

    if command -v apt >/dev/null 2>&1; then
        # Try distro package first
        if apt-cache show fastfetch >/dev/null 2>&1; then
            sudo apt install -y fastfetch
            return
        fi

        echo "fastfetch not found in apt, downloading .deb..."

        ARCH=$(dpkg --print-architecture)

        case "$ARCH" in
            amd64)
                FILE="fastfetch-linux-amd64.deb"
                ;;
            arm64)
                FILE="fastfetch-linux-aarch64.deb"
                ;;
            *)
                echo "Unsupported architecture: $ARCH"
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
        echo "No supported package manager found"
        exit 1
    fi
}

install_fastfetch

echo "Cloning Repo"

REPO="https://github.com/casualtyface/custom-script.git"
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

echo "Backup created: $BACKUP"

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
        echo "$key $value" >> "$CONFIG"
    fi
done

echo "SSH configuration updated."

# Check configuration
sshd -t

if [ $? -eq 0 ]; then
    echo "SSH configuration syntax OK."
    echo "Restart SSH service to apply changes:"
    echo "systemctl restart sshd"
else
    echo "ERROR: SSH configuration test failed. Restore backup:"
    echo "cp $BACKUP $CONFIG"
fi

CONFIG="/etc/pam.d/sshd"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Cannot find $CONFIG"
    exit 1
fi

BACKUP="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

cp "$CONFIG" "$BACKUP"

echo "Backup created: $BACKUP"

RULES=(
"session    optional     pam_motd.so  motd=/run/motd.dynamic"
"session    optional     pam_motd.so noupdate"
"session    optional     pam_mail.so standard noenv"
)

for rule in "${RULES[@]}"; do
    if grep -qF "$rule" "$CONFIG"; then
        sed -i "s|^$rule|#$rule|" "$CONFIG"
        echo "Disabled: $rule"
    else
        echo "Not found: $rule"
    fi
done

echo
echo "Current PAM entries:"
grep -E "pam_motd|pam_mail" "$CONFIG"

systemctl restart sshd

if [ $? -eq 0 ]; then
    echo "SSH service restarted successfully."
    systemctl status sshd --no-pager
else
    echo "ERROR: Failed to restart SSH service."
    echo "Checking SSH configuration:"
    sshd -t
fi

# Add fish to valid login shells if not already present
if ! grep -qx "/usr/local/bin/fish" /etc/shells; then
    echo "/usr/local/bin/fish" | sudo tee -a /etc/shells >/dev/null
fi

# Change current user's shell to fish
chsh -s "$(command -v fish)"

