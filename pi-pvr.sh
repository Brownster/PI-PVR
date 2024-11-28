#!/bin/bash

# Variables
CONTAINER_NETWORK="vpn_network"
DOCKER_DIR="$HOME/docker"
ENV_FILE="$DOCKER_DIR/.env"
TIMEZONE=$(cat /etc/timezone)

# Container Names and Images
VPN_CONTAINER="vpn"
VPN_IMAGE="qmcgaw/gluetun"

JACKETT_CONTAINER="jackett"
JACKETT_IMAGE="linuxserver/jackett"

SONARR_CONTAINER="sonarr"
SONARR_IMAGE="linuxserver/sonarr"

RADARR_CONTAINER="radarr"
RADARR_IMAGE="linuxserver/radarr"

TRANSMISSION_CONTAINER="transmission"
TRANSMISSION_IMAGE="linuxserver/transmission"

NZBGET_CONTAINER="nzbget"
NZBGET_IMAGE="linuxserver/nzbget"

WATCHTOWER_CONTAINER="watchtower"
WATCHTOWER_IMAGE="containrrr/watchtower"

# Exit on error
set -e

# Install required dependencies
install_dependencies() {
    echo "Updating system and installing required packages..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl docker.io docker-compose
    echo "Dependencies installed."
}

# Install and configure Tailscale
setup_tailscale() {
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "Tailscale installed."

    echo "Starting Tailscale and authenticating..."
    if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
        echo "TAILSCALE_AUTH_KEY is not set. Tailscale will require manual authentication."
        sudo tailscale up
    else
        sudo tailscale up --authkey="$TAILSCALE_AUTH_KEY"
    fi

    echo "Tailscale is running."
    echo "Access your server using its Tailscale IP: $(tailscale ip -4)"
    echo "Manage devices at https://login.tailscale.com."
}

# Set up Docker network for VPN containers
setup_docker_network() {
    echo "Creating Docker network for VPN..."
    if docker network create "$CONTAINER_NETWORK"; then
        echo "Docker network '$CONTAINER_NETWORK' created."
    else
        echo "Docker network '$CONTAINER_NETWORK' already exists."
    fi
}

# Create .env file for sensitive data
create_env_file() {
    echo "Creating .env file for sensitive data..."
    mkdir -p "$DOCKER_DIR"
    if [[ ! -f "$ENV_FILE" ]]; then
        cat > "$ENV_FILE" <<EOF
PIA_USERNAME=your_pia_username
PIA_PASSWORD=your_pia_password
TAILSCALE_AUTH_KEY=your_tailscale_auth_key
EOF
        echo ".env file created at $ENV_FILE. Please update it with your credentials."
    else
        echo ".env file already exists. Update credentials if necessary."
    fi
}

# Create Docker Compose file
create_docker_compose() {
    echo "Creating Docker Compose file..."
    cat > "$DOCKER_DIR/docker-compose.yml" <<EOF
version: "3.8"
services:
  $VPN_CONTAINER:
    image: $VPN_IMAGE
    container_name: $VPN_CONTAINER
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    environment:
      - VPN_SERVICE_PROVIDER=pia
      - VPN_TYPE=wireguard
      - VPN_USER=\${PIA_USERNAME}
      - VPN_PASS=\${PIA_PASSWORD}
      - SERVER_COUNTRIES=US
      - TZ=$TIMEZONE
      - LOG_LEVEL=info
    networks:
      - $CONTAINER_NETWORK
    healthcheck:
      test: curl --fail http://localhost:8000 || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  $JACKETT_CONTAINER:
    image: $JACKETT_IMAGE
    container_name: $JACKETT_CONTAINER
    network_mode: service:$VPN_CONTAINER
    depends_on:
      - $VPN_CONTAINER
    ports:
      - "9117:9117"
    volumes:
      - $DOCKER_DIR/downloads:/downloads
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=$TIMEZONE
    restart: unless-stopped

  $SONARR_CONTAINER:
    image: $SONARR_IMAGE
    container_name: $SONARR_CONTAINER
    network_mode: service:$VPN_CONTAINER
    depends_on:
      - $VPN_CONTAINER
    ports:
      - "8989:8989"
    volumes:
      - $DOCKER_DIR/media/tvshows:/tv
      - $DOCKER_DIR/downloads:/downloads
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=$TIMEZONE
    restart: unless-stopped

  $RADARR_CONTAINER:
    image: $RADARR_IMAGE
    container_name: $RADARR_CONTAINER
    network_mode: service:$VPN_CONTAINER
    depends_on:
      - $VPN_CONTAINER
    ports:
      - "7878:7878"
    volumes:
      - $DOCKER_DIR/media/movies:/movies
      - $DOCKER_DIR/downloads:/downloads
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=$TIMEZONE
    restart: unless-stopped

  $TRANSMISSION_CONTAINER:
    image: $TRANSMISSION_IMAGE
    container_name: $TRANSMISSION_CONTAINER
    network_mode: service:$VPN_CONTAINER
    depends_on:
      - $VPN_CONTAINER
    ports:
      - "9091:9091"
    volumes:
      - $DOCKER_DIR/downloads:/downloads
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=$TIMEZONE
    restart: unless-stopped

  $NZBGET_CONTAINER:
    image: $NZBGET_IMAGE
    container_name: $NZBGET_CONTAINER
    network_mode: service:$VPN_CONTAINER
    depends_on:
      - $VPN_CONTAINER
    ports:
      - "6789:6789"
    volumes:
      - $DOCKER_DIR/downloads:/downloads
      - $DOCKER_DIR/media:/media
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=$TIMEZONE
    restart: unless-stopped

  $WATCHTOWER_CONTAINER:
    image: $WATCHTOWER_IMAGE
    container_name: $WATCHTOWER_CONTAINER
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
    network_mode: bridge # Ensure Watchtower bypasses the VPN
    restart: unless-stopped

networks:
  $CONTAINER_NETWORK:
    external: true
EOF
    echo "Docker Compose file created at $DOCKER_DIR/docker-compose.yml"
}

# Deploy Docker Compose stack
deploy_docker_compose() {
    echo "Deploying Docker Compose stack..."
    if ! docker-compose --env-file "$ENV_FILE" -f "$DOCKER_DIR/docker-compose.yml" up -d; then
        echo "Error: Failed to deploy Docker Compose stack."
        exit 1
    fi
    echo "Docker Compose stack deployed successfully."
}

# Main setup function
main() {
    install_dependencies
    setup_tailscale
    setup_docker_network
    create_env_file
    create_docker_compose
    deploy_docker_compose
    echo "Setup complete. Update the .env file with credentials if not already done."
}

main
