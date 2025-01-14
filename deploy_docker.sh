#!/bin/bash

DOCKER_DIR="$HOME/docker"
ENV_FILE="$DOCKER_DIR/.env"

# Source utilities
source ./utils.sh

# Load environment variables
load_env

# Deploy Docker Compose stack
deploy_docker_compose() {
    whiptail --title "Deploy Docker Compose" --msgbox "Starting Docker Compose deployment..." 10 60

    # Check Docker installation
    if ! command -v docker &>/dev/null; then
        whiptail --title "Error" --msgbox "Docker CLI is not installed. Please install Docker before running this script." 10 60
        exit 1
    fi

    # Check Docker group membership
    if ! groups "$USER" | grep -q "docker"; then
        whiptail --title "Docker Group" --msgbox "User '$USER' is not in the 'docker' group. Adding to group..." 10 60
        sudo usermod -aG docker "$USER"
        whiptail --title "Docker Group" --msgbox "User '$USER' has been added to the 'docker' group. Log out and log back in to refresh your session." 10 60
        exit 1
    fi

    local compose_file="$DOCKER_DIR/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        sed -i '/get_iplayer:/,/restart: unless-stopped/ s/^/#/' "$compose_file"
        whiptail --title "Docker Compose" --msgbox "Temporarily disabled get_iplayer container for the first run." 10 60
    else
        whiptail --title "Error" --msgbox "Docker Compose file not found at $compose_file. Aborting deployment." 10 60
        exit 1
    fi

    if docker compose --env-file "$ENV_FILE" -f "$compose_file" up -d; then
        whiptail --title "Success" --msgbox "Docker Compose stack deployed successfully!" 10 60
    else
        whiptail --title "Error" --msgbox "Failed to deploy Docker Compose stack. Check logs for details." 10 60
        exit 1
    fi
}

deploy_docker_compose
