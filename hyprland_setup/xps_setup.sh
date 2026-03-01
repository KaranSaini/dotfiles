
#!/usr/bin/env bash
set -euo pipefail

# ------------------------
# Helper functions
# ------------------------
log() { echo -e "\e[1;34m[INFO]\e[0m $*"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m $*"; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $*"; }

# Install a package if it exists in the repos
install_pkg() {
    local pkg="$1"
    if apt-cache show "$pkg" &>/dev/null; then
        log "Installing $pkg..."
        sudo apt install -y "$pkg"
    else
        warn "Package '$pkg' not found in repositories. Skipping..."
    fi
}

# ------------------------
# Check running as regular user
# ------------------------
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  error "Do not run this script as root. It will use sudo when needed."
  exit 1
fi

# ------------------------
# Verify Ubuntu
# ------------------------
if [[ ! -f /etc/os-release ]]; then
  error "Cannot detect OS. /etc/os-release missing."
  exit 1
fi
. /etc/os-release
if [[ "${ID}" != "ubuntu" ]]; then
  error "This installer supports Ubuntu only."
  exit 1
fi
log "Detected Ubuntu $VERSION_ID"

DOTFILES_REPO="${1:-}"

# ------------------------
# Update & essentials
# ------------------------
sudo apt update
ESSENTIALS=(software-properties-common curl ca-certificates git jq)
for pkg in "${ESSENTIALS[@]}"; do
    install_pkg "$pkg"
done

# ------------------------
# Add Hyprland PPA if needed
# ------------------------
case "${VERSION_ID}" in
  24.04)
    log "Adding Hyprland PPA for Ubuntu 24.04..."
    sudo add-apt-repository -y ppa:cppiber/hyprland
    sudo apt update
    ;;
  *)
    log "Using official packages for Hyprland ($VERSION_ID)"
    ;;
esac

# ------------------------
# Detect GPU and install recommended drivers
# ------------------------
GPU=$(lspci | grep -E "VGA|3D" | head -n1)
log "Detected GPU: $GPU"

if echo "$GPU" | grep -qi "NVIDIA"; then
    log "NVIDIA detected, installing recommended drivers..."
    sudo ubuntu-drivers autoinstall
elif echo "$GPU" | grep -qi "AMD"; then
    log "AMD detected, Mesa drivers should suffice."
elif echo "$GPU" | grep -qi "Intel"; then
    log "Intel detected, Mesa drivers should suffice."
else
    warn "Unknown GPU. Drivers may need manual setup."
fi

# ------------------------
# Install Hyprland + dependencies (optional deps handled gracefully)
# ------------------------
HYPR_PACKAGES=(
  hyprland
  xdg-desktop-portal-hyprland
  waybar
  wofi
  alacritty
  hyprpaper
  wl-clipboard
  grim
  slurp
  swww      # may not exist in Ubuntu
  brightnessctl
  playerctl
  pavucontrol
  policykit-1-gnome
  libinput-tools
)

for pkg in "${HYPR_PACKAGES[@]}"; do
    install_pkg "$pkg"
done

# ------------------------
# Create config directories
# ------------------------
mkdir -p ~/.config/hypr ~/.config/waybar

# ------------------------
# Pull dotfiles if provided
# ------------------------
if [[ -n "${DOTFILES_REPO}" ]]; then
    log "Cloning dotfiles from $DOTFILES_REPO"
    tmp="$(mktemp -d)"
    git clone --depth=1 "$DOTFILES_REPO" "$tmp"
    rsync -a --ignore-missing-args "$tmp/hypr/" ~/.config/hypr/ 2>/dev/null || true
    rsync -a --ignore-missing-args "$tmp/waybar/" ~/.config/waybar/ 2>/dev/null || true
    rm -rf "$tmp"
fi

# ------------------------
# Detect screen resolution for scaling
# ------------------------
if command -v xdpyinfo &>/dev/null; then
    SCREEN_WIDTH=$(xdpyinfo | grep dimensions | awk '{print $2}' | cut -d'x' -f1)
    if [[ "$SCREEN_WIDTH" -ge 3840 ]]; then
        SCALE=1.5
    elif [[ "$SCREEN_WIDTH" -ge 2560 ]]; then
        SCALE=1.25
    else
        SCALE=1.0
    fi
else
    warn "xdpyinfo not found. Defaulting scale to 1.25"
    SCALE=1.25
fi
log "Using scaling factor: $SCALE"

# ------------------------
# Create minimal Hyprland config if missing
# ------------------------
if [[ ! -s ~/.config/hypr/hyprland.conf ]]; then
    log "Creating default Hyprland config"
    cat > ~/.config/hypr/hyprland.conf <<EOF
monitor=,preferred,auto,${SCALE}
\$mod = SUPER

# Launchers / apps
bind = \$mod, RETURN, exec, alacritty
bind = \$mod, D, exec, wofi --show drun
bind = \$mod, Q, killactive,
bind = \$mod, F, fullscreen,

# Move focus keys
bind = \$mod, H, movefocus, l
bind = \$mod, J, movefocus, d
bind = \$mod, K, movefocus, u
bind = \$mod, L, movefocus, r

# Screenshots
bind = ,Print, exec, grim - | wl-copy
bind = SHIFT, Print, exec, grim -g "\$(slurp -w 0)" - | wl-copy

# Animations / wallpaper
animations=1
exec-once = hyprpaper
exec-once = waybar

# Optional gestures (if libinput-gestures installed)
if command -v libinput-gestures &>/dev/null; then
    exec-once = "libinput-gestures-setup start"
fi
EOF
fi

# ------------------------
# Minimal Waybar config if missing
# ------------------------
if [[ ! -s ~/.config/waybar/config.jsonc ]]; then
    log "Creating default Waybar config"
    cat > ~/.config/waybar/config.jsonc <<EOF
{
  "layer": "top",
  "position": "top",
  "modules-left": ["workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["cpu", "memory", "battery", "pulseaudio", "network"],
  "clock": { "format": "{:%a %b %d  %H:%M}" },
  "animation": { "enabled": true }
}
EOF
fi

# ------------------------
# Restart portals
# ------------------------
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-hyprland || warn "Could not restart portals"

log "✅ XPS 15 Hyprland setup complete!"
log "Log out, select 'Hyprland' at the login screen, then log in."
log "You can adjust scaling in ~/.config/hypr/hyprland.conf if needed."

