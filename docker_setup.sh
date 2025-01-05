#!/bin/bash

DOCKER_DIR="$HOME/docker"
ENV_FILE="$DOCKER_DIR/.env"

# Source utilities
source ./utils.sh

# Load environment variables
load_env


# Ensure DOCKER_DIR exists
ensure_docker_dir() {
    if [[ ! -d "$DOCKER_DIR" ]]; then
        whiptail --title "Create $VPN_CONTAINER config" --msgbox "Creating Docker directory at $DOCKER_DIR..." 10 60
        mkdir -p "$DOCKER_DIR"
    fi

    if [[ ! -f "$ENV_FILE" ]]; then
        whiptail --title "Create $VPN_CONTAINER config" --msgbox  "Creating .env file at $ENV_FILE..." 10 60
        touch "$ENV_FILE"
        chmod 600 "$ENV_FILE"
    fi
}




# Create Docker Compose file
create_docker_compose() {
    if [[ "$docker_compose_success" == "1" ]]; then
        whiptail --title "Docker Compose" --msgbox  "Docker Compose stack is already deployed. Skipping." 10 60
        return
    fi    

    whiptail --title "Docker Compose" --msgbox  "Creating Docker Compose file from repository..." 10 60
    
    # Directory to save the Docker Compose file
    mkdir -p "$DOCKER_DIR"

    # Download the Docker Compose file
    if curl -fSL "$COMPOSE_URL" -o "$DOCKER_DIR/docker-compose.yml"; then
        whiptail --title "Docker Compose" --msgbox  "Docker Compose file downloaded successfully to $DOCKER_DIR/docker-compose.yml" 10 60

    fi    
    sed -i 's/docker_compose_success=0/docker_compose_success=1/' "$ENV_FILE"
}


# Set up Docker network for VPN containers
setup_docker_network() {
    if [[ "$DOCKER_NETWORK_SUCCESS" == "1" ]]; then
        whiptail --title "Docker Network" --msgbox "Docker Network is already set up. Skipping." 10 60
        return
    fi

    whiptail --title "Docker Network" --msgbox "Setting up Docker network for VPN..." 10 60

    if ! systemctl is-active --quiet docker; then
        whiptail --title "Docker Service" --msgbox "Starting Docker service..." 10 60
        sudo systemctl start docker
    fi

    if sudo docker network ls | grep -q "$CONTAINER_NETWORK"; then
        whiptail --title "Docker Network" --msgbox "Docker network '$CONTAINER_NETWORK' already exists." 10 60
    else
        sudo docker network create "$CONTAINER_NETWORK"
        whiptail --title "Docker Network" --msgbox "Docker network '$CONTAINER_NETWORK' created." 10 60
        sed -i 's/DOCKER_NETWORK_SUCCESS=0/DOCKER_NETWORK_SUCCESS=1/' "$ENV_FILE"
    fi
}
