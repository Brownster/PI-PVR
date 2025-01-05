#!/bin/bash

DOCKER_DIR="$HOME/docker"
ENV_FILE="$DOCKER_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    whiptail --title "Deploy Docker Compose" --msgbox "Error: .env file not found at $ENV_FILE" 10 60
    exit 1
fi


# Deploy Docker Compose stack
deploy_docker_compose() {
    whiptail --title "Deploy Docker Compose" --msgbox "Starting Docker Compose deployment..." 10 60

    # Check Docker group membership
    if ! groups "$USER" | grep -q "docker"; then
        whiptail --title "Docker Group" --msgbox "User '$USER' is not in the 'docker' group. Adding to group..." 10 60
        sudo usermod -aG docker "$USER"
        whiptail --title "Docker Group" --msgbox "User '$USER' has been added to the 'docker' group. Please log out and log back in, then restart this script." 10 60
        exit 1
    fi

    # Temporarily disable get_iplayer in docker-compose.yml
    local compose_file="$DOCKER_DIR/docker-compose.yml"
    if [ -f "$compose_file" ]; then
        sed -i '/get_iplayer:/,/restart: unless-stopped/ s/^/#/' "$compose_file"
        whiptail --title "Docker Compose" --msgbox "Disabled get_iplayer container for the first run." 10 60
    else
        whiptail --title "Error" --msgbox "Docker Compose file not found at $compose_file. Aborting deployment." 10 60
        exit 1
    fi

    # Attempt to deploy the Docker Compose stack
    if ! docker compose --env-file "$ENV_FILE" -f "$compose_file" up -d; then
        whiptail --title "Error" --msgbox "Failed to deploy Docker Compose stack. This may be due to recent Docker permission changes. Please log out and log back in to refresh your session, then restart this script." 15 60
        exit 1
    fi

    whiptail --title "Success" --msgbox "Docker Compose stack deployed successfully. Retrieve the API keys for Radarr and Sonarr, and update the .env file." 10 60

    # Notify user to uncomment get_iplayer and restart the stack
    whiptail --title "Next Steps" --msgbox "To enable get_iplayer, uncomment its section in the Docker Compose file after adding the API keys:\n\nsed -i '/#get_iplayer:/,/restart: unless-stopped/ s/^#//' \"$compose_file\"\n\nThen, redeploy the stack." 15 70
}
