#!/bin/bash

DOCKER_DIR="$HOME/docker"

# Check and source the .env file
ENV_FILE="$DOCKER_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

#Detect Linux Distro
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        whiptail --title "Error" --msgbox "Unsupported Linux distribution." 10 60
        exit 1
    fi
}

#Alter install based on $DISTRO
install_package() {
    case $DISTRO in
        ubuntu|debian)
            sudo apt-get install -y "$@"
            ;;
        fedora|centos|rhel)
            sudo dnf install -y "$@"
            ;;
        arch)
            sudo pacman -S --noconfirm "$@"
            ;;
        *)
            whiptail --title "Error" --msgbox "Unsupported Linux distribution: $DISTRO" 10 60
            exit 1
            ;;
    esac
}

# Write Distro to .env file
write_distro_to_env() {
    if grep -q "^DISTRO=" "$ENV_FILE"; then
        sed -i "s/^DISTRO=.*/DISTRO=$DISTRO/" "$ENV_FILE"
    else
        echo "DISTRO=$DISTRO" >> "$ENV_FILE"
    fi
}

# Function to update /etc/fstab with the new mount point
update_fstab() {
    local mount_point="$1"
    local device="$2"

    # Get the UUID of the device
    local uuid=$(blkid -s UUID -o value "$device")
    if [[ -z "$uuid" ]]; then
        whiptail --title "error" --msgbox   "Error: Could not retrieve UUID for device $device."
        exit 1
    fi

    # Check if the mount point is already in /etc/fstab
    if grep -q "$mount_point" /etc/fstab; then
        whiptail --title "Fstab" --msgbox "Mount point $mount_point already exists in /etc/fstab. Skipping." 10 60
    else
        whiptail --title "Fstab" --msgbox "Adding $mount_point to /etc/fstab..."
        echo "UUID=$uuid $mount_point auto defaults 0 2" | sudo tee -a /etc/fstab > /dev/null
    fi
}
