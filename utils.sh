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


install_package() {
    case $DISTRO in
        ubuntu|debian)
            if [[ "$1" == "remove" ]]; then
                shift
                echo "Removing packages with apt-get: $*"
                sudo apt-get remove -y "$@"
            else
                echo "Updating package database with apt-get..."
                sudo apt-get update
                echo "Installing packages with apt-get: $*"
                sudo apt-get install -y "$@"
            fi
            ;;
        fedora|centos|rhel)
            if [[ "$1" == "remove" ]]; then
                shift
                echo "Removing packages with dnf: $*"
                sudo dnf remove -y "$@"
            else
                echo "Updating package database with dnf..."
                sudo dnf upgrade -y
                echo "Installing packages with dnf: $*"
                sudo dnf install -y "$@"
            fi
            ;;
        arch)
            if [[ "$1" == "remove" ]]; then
                shift
                echo "Removing packages with pacman: $*"
                sudo pacman -Rns --noconfirm "$@"
            else
                echo "Updating package database with pacman..."
                sudo pacman -Syu --noconfirm
                echo "Installing packages with pacman: $*"
                sudo pacman -S --noconfirm "$@"
            fi
            ;;
        *)
            echo "Unsupported Linux distribution: $DISTRO"
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
