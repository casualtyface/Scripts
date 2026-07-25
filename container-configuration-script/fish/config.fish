if status is-interactive
    # Commands to run in interactive sessions can go here
    clear
    fastfetch
    set -U fish_greeting
end

# Set settings for https://github.com/franciscolourenco/done
set -U __done_min_cmd_duration 10000
set -U __done_notification_urgency_level low

## Useful aliases
# Replace ls with exa
alias ls='exa -al --color=always --group-directories-first --icons' # preferred listing
alias la='exa -a --color=always --group-directories-first --icons'  # all files and dirs
alias ll='exa -l --color=always --group-directories-first --icons'  # long format
alias lt='exa -aT --color=always --group-directories-first --icons' # tree listing
alias l.="exa -a | egrep '^\.'"                                     # show only dotfiles
alias ip="ip -color"

# Common use
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias cat='batcat'
alias cfastfetch='clear && fastfetch'

# Other
alias emacs="emacsclient -c -a 'emacs'" 
alias upall='apt-get update && apt-get dist-upgrade -y'
#alias Font-Install='sudo pacman -Syu $(sudo pacman -Ssq ttf-)'
alias gbtyp='pacman -Qtdq | sudo pacman -Rns -'

# Cd Aliases
alias cd.fish='cd ~/.config/fish/'

# Vim Config Aliases
alias v.fish='vim ~/.config/fish/config.fish'
alias v.grub='vim /etc/default/grub'

# Get the error messages from journalctl
alias jctl='journalctl -p 3 -xb'

#Update the grub bootloader
alias grub-up='sudo grub-mkconfig -o /boot/grub/grub.cfg'

zoxide init --cmd cd fish | source