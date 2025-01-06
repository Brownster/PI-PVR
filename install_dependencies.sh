#!/bin/bash
# variables
DOCKER_DIR="$HOME/docker"
# Source utilities
source ./utils.sh

# Load environment variables
load_env

# Install required dependencies
install_dependencies() {
    echo "Entering install_dependencies function"
    load_env
    if [[ "$INSTALL_DEPENDANCIES_SUCCESS" == "1" ]]; then
        whiptail --title "Install Dependencies" --msgbox "Dependencies are already installed. Skipping." 10 60
        return
    fi

    # Install required dependencies
    whiptail --title "Install Dependencies" --msgbox "Installing core dependencies (curl, jq, git)..." 10 60
    install_package curl jq git

    # Remove old Docker packages
    whiptail --title "Install Dependencies" --msgbox "Removing old Docker packages..." 10 60
    install_package remove docker.io docker-doc docker-compose podman-docker containerd runc

    # Add Docker's GPG key and repository
    whiptail --title "Install Dependencies" --msgbox "Adding Docker's official GPG key and repository..." 10 60
    case $DISTRO in
        ubuntu|debian)
            sudo install -m 0755 -d /etc/apt/keyrings
            sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            sudo chmod a+r /etc/apt/keyrings/docker.asc
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                VERSION_CODENAME=${VERSION_CODENAME:-$(lsb_release -cs)}
            fi
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
            $VERSION_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            ;;
        fedora|centos|rhel)
            sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
            sudo dnf makecache
            ;;
        arch)
            echo "Docker repository already available in Arch Linux."
            ;;
        *)
            whiptail --title "Error" --msgbox "Unsupported Linux distribution for Docker repository setup." 10 60
            exit 1
            ;;
    esac

    # Install Docker Engine and Compose
    whiptail --title "Install Dependencies" --msgbox "Installing Docker Engine and Docker Compose..." 10 60
    install_package docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Confirm success
    whiptail --title "Install Dependencies" --msgbox "All dependencies installed successfully." 10 60

    # Update .env file to reflect success
    sed -i 's/INSTALL_DEPENDANCIES_SUCCESS=0/INSTALL_DEPENDANCIES_SUCCESS=1/' "$ENV_FILE"
}
