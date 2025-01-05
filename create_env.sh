#!/bin/bash
# Variables
DOCKER_DIR="$HOME/docker"
ENV_FILE="$DOCKER_DIR/.env"
ENV_URL="https://raw.githubusercontent.com/Brownster/docker-compose-pi/refs/heads/main/.env"

# Create .env file for sensitive data
create_env_file() {
    if whiptail --title "Setup" --yesno "Do you want to download a new .env file?" 10 60; then
        mkdir -p "$DOCKER_DIR"

        # URL of the .env file in the repository
        ENV_URL="https://raw.githubusercontent.com/Brownster/docker-compose-pi/refs/heads/main/.env"

        if curl -fSL "$ENV_URL" -o "$ENV_FILE"; then
            whiptail --title "Success" --msgbox ".env file downloaded successfully." 10 60
            chmod 600 "$ENV_FILE"
        else
            whiptail --title "Error" --msgbox "Failed to download .env file." 10 60
            exit 1
        fi
    else
        whiptail --title "Skipped" --msgbox "Using existing .env file if available." 10 60
    fi
}
