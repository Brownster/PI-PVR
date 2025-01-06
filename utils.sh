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

# Load the environment
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    else
        echo "Error: .env file not found at $ENV_FILE"
        exit 1
    fi
}

# Detect Linux Distro
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        whiptail --title "Error" --msgbox "Unsupported Linux distribution." 10 60
        exit 1
    fi
}

# Write Distro to .env file
write_distro_to_env() {
    if grep -q "^DISTRO=" "$ENV_FILE"; then
        sed -i "s/^DISTRO=.*/DISTRO=$DISTRO/" "$ENV_FILE"
    else
        echo "#host Distro" >> "$ENV_FILE"
        echo "DISTRO=$DISTRO" >> "$ENV_FILE"
    fi
    whiptail --title "Success" --msgbox "Detected distro: $DISTRO. Updated .env file." 10 60
}


# change package manager depending on distro
install_package() {
    # Detect Linux Distro if DISTRO is not already set
    if [[ -z "${DISTRO:-}" ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
        else
            whiptail --title "Error" --msgbox "Unsupported Linux distribution. Unable to detect distro." 10 60
            exit 1
        fi
    fi

    echo "Detected DISTRO: $DISTRO"

    # Install packages based on detected distro
    case $DISTRO in
        ubuntu|debian)
            echo "Using apt to install: $*"
            sudo apt-get update
            sudo apt-get install -y "$@"
            ;;
        fedora|centos|rhel)
            echo "Using dnf to install: $*"
            sudo dnf install -y "$@"
            ;;
        arch)
            echo "Using pacman to install: $*"
            sudo pacman -Syu --noconfirm
            sudo pacman -S --noconfirm "$@"
            ;;
        *)
            whiptail --title "Error" --msgbox "Unsupported Linux distribution: $DISTRO" 10 60
            exit 1
            ;;
    esac
}


# Main Execution
#main() {
#    detect_distro
#    write_distro_to_env
#    whiptail --title "Success" --msgbox "Detected distro: $DISTRO. Updated .env file." 10 60
#}

#main
