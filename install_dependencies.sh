#!/bin/bash
# variables
DOCKER_DIR="$HOME/docker"
# Source utilities
source ./utils.sh

# Load environment variables
load_env

# Install required dependencies
install_dependencies() {
    load_env
    if [[ "$INSTALL_DEPENDANCIES_SUCCESS" == "1" ]]; then
        whiptail --title "Install Dependancies" --msgbox "Docker Compose stack is already deployed. Skipping." 10 60
        return
    fi

    # Install required dependencies, including git
    whiptail --title "Install Dependancies" --msgbox "Installing dependencies..." 10 60
    sudo apt update
    sudo apt install -y curl jq git

    whiptail --title "Install Dependancies" --msgbox  "Uninstalling any conflicting Docker packages..." 10 60
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        sudo install_package remove -y "$pkg"
    done

    whiptail --title "Install Dependancies" --msgbox  "Adding Docker's official GPG key and repository for Docker..." 10 60
    sudo install_package update
    sudo install_package install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo install_package update

    whiptail --title "Install Dependancies" --msgbox  "Installing Docker Engine, Docker Compose, and related packages..." 10 60
    sudo install_package install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    whiptail --title "Install Dependancies" --msgbox  "Installing other required dependencies: curl, jq, git..." 10 60
    sudo install_package install -y curl jq git

    whiptail --title "Install Dependancies" --msgbox  "Verifying Docker installation..." 10 60
    #sudo docker run hello-world

    whiptail --title "Install Dependancies" --msgbox  "All dependencies installed successfully." 10 60

    sed -i 's/INSTALL_DEPENDANCIES_SUCCESS=0/INSTALL_DEPENDANCIES_SUCCESS=1/' "$ENV_FILE"
}
