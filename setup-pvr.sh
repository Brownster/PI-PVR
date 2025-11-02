#!/bin/bash
# Server Variables
SERVER_IP=$(hostname -I | awk '{print $1}')
# General Variables
CONTAINER_NETWORK="vpn_network"
DOCKER_DIR="$HOME/docker"
ENV_FILE="$DOCKER_DIR/.env"

# Exit on error
set -euo pipefail

# Toggle debug mode: true = show all outputs, false = suppress outputs
DEBUG=true  # Set to 'false' to suppress command outputs

# Function to handle command output based on DEBUG flag
run() {
    if [ "$DEBUG" = true ]; then
        "$@"  # Run commands normally, show output
    else
        "$@" >/dev/null 2>&1  # Suppress output
    fi
}

# Create .env file for sensitive data
create_env_file() {
    echo "Creating .env file for sensitive data..."
    mkdir -p "$DOCKER_DIR"
    if [[ ! -f "$ENV_FILE" ]]; then
        read -r -p "Enter your PIA_USERNAME: " PIA_USERNAME
        read -r -s -p "Enter your PIA_PASSWORD: " PIA_PASSWORD
        echo ""
        read -r -p "Enter your TAILSCALE_AUTH_KEY (or press Enter to skip): " TAILSCALE_AUTH_KEY


        cat > "$ENV_FILE" <<EOF
#General Docker
DOCKER_DIR="$HOME/docker"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/Brownster/docker-compose-pi/refs/heads/main/docker-compose.yml"

# Docker Configuration (Optional)
TIMEZONE=Europe/London
IMAGE_RELEASE="latest"
PUID=1000
PGID=1000

# Media folder names
MOVIES_FOLDER="Movies"       # Name of the folder for movies/films/kids films etc
TVSHOWS_FOLDER="TVShows"     # Name of the folder for TV shows/TV/kids TV etc
DOWNLOADS="/mnt/downloads"
STORAGE_MOUNT="/mnt/storage"
BACKUP_MOUNT="/mnt/backup"

#Tailscale
TAILSCALE_AUTH_KEY=$TAILSCALE_AUTH_KEY

#PORTS
JACKET_PORT="9117"
SONARR_PORT="8989"
RADARR_PORT="7878"
TRANSMISSION_PORT="9091"
NZBGET="6789"
GET_IPLAYER_PORT="1935"
MEDIASERVER_HTTP="8096"
MEDIASERVER_HTTPS="8920"

# VPN Configuration
PIA_USERNAME=$PIA_USERNAME
PIA_PASSWORD=$PIA_PASSWORD
VPN_CONTAINER="vpn"
VPN_IMAGE="qmcgaw/gluetun"
CONTAINER_NETWORK="vpn_network"

#Jacket
JACKETT_CONTAINER="jackett"
JACKETT_IMAGE="linuxserver/jackett"

#Sonarr
SONARR_CONTAINER="sonarr"
SONARR_IMAGE="linuxserver/sonarr"
SONARR_API_KEY="your_sonarr_api_key"   # Replace with actual API key after install

#Radarr
RADARR_CONTAINER="radarr"
RADARR_IMAGE="linuxserver/radarr"
RADARR_API_KEY="your_radarr_api_key"   # Replace with actual API key after install

#Transmission
TRANSMISSION_CONTAINER="transmission"
TRANSMISSION_IMAGE="linuxserver/transmission"
#NZBGet
NZBGET_CONTAINER="nzbget"
NZBGET_IMAGE="linuxserver/nzbget"

#Get Iplayer
GET_IPLAYER="get_iplayer"
GET_IPLAYER_IMAGE="ghcr.io/thespad/get_iplayer
INCLUDERADIO="true"
ENABLEIMPORT="true"

#JellyFin
JELLYFIN_CONTAINER="jellyfin"
JELLYFIN_IMAGE="linuxserver/jellyfin"

#WatchTower
WATCHTOWER_CONTAINER="watchtower"
WATCHTOWER_IMAGE="containrrr/watchtower"

#Track runs
tailscale_install_success=0
PIA_SETUP_SUCCESS=0
docker_install_success=0
pia_vpn_setup_success=0
docker_compose_success=0
CREATE_CONFIG_SUCCESS=0
INSTALL_DEPENDANCIES_SUCCESS=0
DOCKER_NETWORK_SUCCESS=0
EOF
        echo ".env file created at $ENV_FILE."
        chmod 600 "$ENV_FILE"
    else
        echo ".env file already exists. Update credentials if necessary."
    fi
}


#GET_IPLAYER CONFIG CREATION
create_config_json() {
    if [[ "$CREATE_CONFIG_SUCCESS" == "1" ]]; then
        echo "IPlayer Get config already setup. Skipping."
        return
    fi
    echo "Creating config.json for SonarrAutoImport..."

    # Define paths
    CONFIG_DIR="$DOCKER_DIR/get_iplayer/config"
    CONFIG_FILE="$CONFIG_DIR/config.json"

    # Ensure the directory exists
    mkdir -p "$CONFIG_DIR"

    # Generate the config.json file
    cat > "$CONFIG_FILE" <<EOF
{
  "radarr": {
    "url" : "http://127.0.0.1:${RADARR_PORT}",
    "apiKey" : "${RADARR_API_KEY}",
    "mappingPath" : "/downloads/",
    "downloadsFolder" : "${DOWNLOADS}/complete",
    "importMode" : "Move",
    "timeoutSecs" : "5"
  },
  "sonarr": {
    "url" : "http://127.0.0.1:${SONARR_PORT}",
    "apiKey" : "${SONARR_API_KEY}",
    "mappingPath" : "/downloads/",
    "downloadsFolder" : "${DOWNLOADS}/complete",
    "importMode" : "Copy",
    "timeoutSecs" : "5",
    "trimFolders" : "true",
    "transforms" : [
      {
        "search" : "Escape_to_the_Country_Series_(\d+)_-_S(\d+)E(\d+)_-_.+\.mp4",
        "replace" : "Escape to the Country S$2E$3.mp4"
      },
      {
        "search" : "Escape_to_the_Country_Series_(\d+)_Extended_Versions_-_S(\d+)E(\d+)_-_.+\.mp4",
        "replace" : "Escape to the Country Extended S$2E$3.mp4"
      },
      {
        "search" : "Escape_to_the_Country_Series_(\d+)_-_Episode_(\d+)\.mp4",
        "replace" : "Escape to the Country S$1E$2.mp4"
      },
      {
        "search" : "Escape_to_the_Country_(\d{4})_Season_(\d+)_-_Episode_(\d+)\.mp4",
        "replace" : "Escape to the Country S$2E$3.mp4"
      }
    ]
  }
}
EOF

    # Update permissions
    chmod 600 "$CONFIG_FILE"

    echo "config.json created at $CONFIG_FILE."
    echo "Please update the API keys in the config file before running the container."
    sed -i 's/CREATE_CONFIG_SUCCESS=0/CREATE_CONFIG_SUCCESS==1/' "$ENV_FILE"
}

# Install and configure Tailscale
setup_tailscale() {
    if [[ "$tailscale_install_success" == "1" ]]; then
        echo "Tailscale is already installed. Skipping."
        return
    fi

    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "Tailscale installed."

    echo "Starting Tailscale and authenticating..."
    if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
        echo "TAILSCALE_AUTH_KEY is not set. Tailscale will require manual authentication."
        sudo tailscale up --accept-routes=false
    else
        sudo tailscale up --accept-routes=false --authkey="$TAILSCALE_AUTH_KEY"
    fi

    echo "Tailscale is running."
    echo "Access your server using its Tailscale IP: $(tailscale ip -4)"
    echo "Manage devices at https://login.tailscale.com."
    # Mark success
    sed -i 's/tailscale_install_success=0/tailscale_install_success=1/' "$ENV_FILE"
}

setup_pia_vpn() {
    if [[ "$PIA_SETUP_SUCCESS" == "1" ]]; then
        echo "PIA already setup. Skipping."
        return
    fi

    echo "Setting up PIA OpenVPN VPN..."

    # Source the .env file to load PIA credentials
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    else
        echo "Error: .env file not found. Ensure you have run create_env_file first."
        exit 1
    fi

    # Ensure PIA credentials are set
    if [[ -z "$PIA_USERNAME" || -z "$PIA_PASSWORD" ]]; then
        echo "Error: PIA credentials are not set. Ensure PIA_USERNAME and PIA_PASSWORD are correctly provided in the .env file."
        exit 1
    fi

    # Create the gluetun directory for configuration
    GLUETUN_DIR="$DOCKER_DIR/$VPN_CONTAINER"
    echo "Creating Gluetun configuration directory at $GLUETUN_DIR..."
    mkdir -p "$GLUETUN_DIR"
    cp -r vpn/* "$GLUETUN_DIR/"


    # Write the environment variables to a Docker Compose file
    cat > "$GLUETUN_DIR/.env" <<EOF
VPN_SERVICE_PROVIDER=private internet access
OPENVPN_USER=$PIA_USERNAME
OPENVPN_PASSWORD=$PIA_PASSWORD
SERVER_REGIONS=Netherlands
EOF

    echo "OpenVPN setup complete. Configuration saved to $GLUETUN_DIR/.env."
    # Mark success
    sed -i 's/PIA_SETUP_SUCCESS=0/PIA_SETUP_SUCCESS=1/' "$ENV_FILE"
}

# Install required dependencies
install_dependencies() {
    if [[ "$INSTALL_DEPENDANCIES_SUCCESS" == "1" ]]; then
        echo "Docker Compose stack is already deployed. Skipping."
        return
    fi

    # Install required dependencies, including git
    echo "Installing dependencies..."
    sudo apt update
    sudo apt install -y curl jq git

    echo "Uninstalling any conflicting Docker packages..."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        sudo apt-get remove -y "$pkg"
    done

    echo "Adding Docker's official GPG key and repository for Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update

    echo "Installing Docker Engine, Docker Compose, and related packages..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Installing other required dependencies: curl, jq, git..."
    sudo apt-get install -y curl jq git

    echo "Verifying Docker installation..."
    sudo docker run hello-world

    echo "All dependencies installed successfully."

    sed -i 's/INSTALL_DEPENDANCIES_SUCCESS=0/INSTALL_DEPENDANCIES_SUCCESS=1/' "$ENV_FILE"
}


# Set up Docker network for VPN containers
setup_docker_network() {
    if [[ "$DOCKER_NETWORK_SUCCESS" == "1" ]]; then
        echo "Docker Network is already deployed. Skipping."
        return
    fi
    echo "Creating Docker network for VPN..."
    if ! systemctl is-active --quiet docker; then
        echo "Docker is not running. Starting Docker..."
        sudo systemctl start docker
    fi

    if sudo docker network ls | grep -q "$CONTAINER_NETWORK"; then
        echo "Docker network '$CONTAINER_NETWORK' already exists."
    else
        sudo docker network create "$CONTAINER_NETWORK"
        echo "Docker network '$CONTAINER_NETWORK' created."
        sed -i 's/DOCKER_NETWORK_SUCCESS=0/DOCKER_NETWORK_SUCCESS=1/' "$ENV_FILE"
    fi
}


# Deploy Docker Compose stack
deploy_docker_compose() {
    echo "Deploying Docker Compose stack..."

    # Check Docker group membership
    if ! groups "$USER" | grep -q "docker"; then
        echo "User '$USER' is not yet in the 'docker' group. Adding to group..."
        sudo usermod -aG docker "$USER"
        echo "User '$USER' has been added to the 'docker' group."
        echo "Please log out and log back in, then restart this script."
        exit 1
    fi

    # Attempt to deploy Docker Compose stack
    if ! docker compose --env-file "$ENV_FILE" -f "$DOCKER_DIR/docker-compose.yml" up -d; then
        echo "Error: Failed to deploy Docker Compose stack."
        echo "This is likely due to recent changes to Docker permissions."
        echo "Please log out and log back in to refresh your user session, then restart this script."
        exit 1
    fi

    echo "Docker Compose stack deployed successfully."
}


setup_mount_and_docker_start() {
    echo "Configuring drives to mount at boot and Docker to start afterwards..."

    # Create systemd service for Docker start
    echo "Creating systemd service to start Docker containers after mounts..."
    sudo bash -c "cat > /etc/systemd/system/docker-compose-start.service" <<EOF
[Unit]
Description=Ensure drives are mounted and start Docker containers
Requires=local-fs.target
After=local-fs.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check_mount_and_start.sh
RemainAfterExit=yes
Environment=HOME=$HOME

[Install]
WantedBy=multi-user.target
EOF

    # Create the script to check mounts and start Docker
    sudo bash -c "cat > /usr/local/bin/check_mount_and_start.sh" <<'EOF'
#!/bin/bash

STORAGE_MOUNT="/mnt/storage"
DOWNLOAD_MOUNT="/mnt/downloads"
BACKUP_MOUNT="/mnt/backup"
DOCKER_COMPOSE_FILE="$HOME/docker/docker-compose.yml"

# Wait until mounts are ready
until mountpoint -q "$STORAGE_MOUNT" && mountpoint -q "$DOWNLOAD_MOUNT" && mountpoint -q "$BACKUP_MOUNT"; do
    echo "Waiting for drives to be mounted..."
    sleep 5
done

echo "Drives are mounted. Starting Docker containers..."
docker compose -f "$DOCKER_COMPOSE_FILE" up -d
EOF

    # Make the script executable
    sudo chmod +x /usr/local/bin/check_mount_and_start.sh

    # Enable and start the systemd service
    sudo systemctl enable docker-compose-start.service
    sudo systemctl start docker-compose-start.service

    echo "Configuration complete. Docker containers will start after drives are mounted on reboot."
}


# Function to pull the latest docker-compose.yml
update_compose_file() {
    echo "Checking for updates to docker-compose.yml..."
    TEMP_COMPOSE_FILE=$(mktemp)

    # URL for your GitHub-hosted docker-compose.yml
    DOCKER_COMPOSE_URL="${DOCKER_COMPOSE_URL}"

    # Download the latest docker-compose.yml from GitHub
    curl -fsSL "$DOCKER_COMPOSE_URL" -o "$TEMP_COMPOSE_FILE"

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to fetch the latest docker-compose.yml from GitHub."
        rm -f "$TEMP_COMPOSE_FILE"
        exit 1
    fi

    # Compare checksums of the current and new files
    LOCAL_COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
    LOCAL_CHECKSUM=$(md5sum "$LOCAL_COMPOSE_FILE" 2>/dev/null | awk '{print $1}')
    REMOTE_CHECKSUM=$(md5sum "$TEMP_COMPOSE_FILE" | awk '{print $1}')

    if [[ "$LOCAL_CHECKSUM" == "$REMOTE_CHECKSUM" ]]; then
        echo "No updates found for docker-compose.yml."
        rm -f "$TEMP_COMPOSE_FILE"
    else
        echo "Update found. Applying changes..."
        mv "$TEMP_COMPOSE_FILE" "$LOCAL_COMPOSE_FILE"
        echo "Redeploying Docker stack..."
        docker compose -f "$LOCAL_COMPOSE_FILE" pull
        docker compose -f "$LOCAL_COMPOSE_FILE" up -d
        echo "Docker stack updated successfully."
    fi
}



# Main setup function
main() {
    # Parse command-line arguments
    for arg in "$@"; do
        case $arg in
            --update)
                update_compose_file
                exit 0
                ;; 
            --debug)
                DEBUG=true
                ;; 
            *)
                echo "Unknown option: $arg"
                echo "Usage: $0 [--update] [--debug]"
                exit 1
                ;; 
        esac
    done
    echo "Starting setup..."
    create_env_file
    # Source the .env file after creating it
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi
    setup_tailscale
    install_dependencies
    setup_pia_vpn
    cp docker-compose.yaml "$DOCKER_DIR/docker-compose.yml"
    create_config_json
    setup_docker_network
    deploy_docker_compose
    setup_mount_and_docker_start
    echo "Setup complete. Update the .env file with credentials if not already done."
    echo "Setup Summary:"
    echo "Docker services are running:"

    # Define the base URL using the server IP
    BASE_URL="http://${SERVER_IP}"

    # Define a list of services with their ports and URLs
    declare -A SERVICES_AND_PORTS=(
        ["VPN"]="${BASE_URL}"
        ["Jackett"]="${BASE_URL}:${JACKET_PORT}"
        ["Sonarr"]="${BASE_URL}:${SONARR_PORT}"
        ["Radarr"]="${BASE_URL}:${RADARR_PORT}"
        ["Transmission"]="${BASE_URL}:${TRANSMISSION_PORT}"
        ["NZBGet"]="${BASE_URL}:${NZBGET_PORT}"
        ["Get_IPlayer"]="${BASE_URL}:${GET_IPLAYER_PORT}"
        ["JellyFin"]="${BASE_URL}:${JELLYFIN_PORT}"
        ["Watchtower"]="(Auto-Updater - no web UI)"
    )

    # Display services and clickable URLs
    echo "Services and their URLs:"
    for SERVICE in "${!SERVICES_AND_PORTS[@]}"; do
        echo "  - $SERVICE: ${SERVICES_AND_PORTS[$SERVICE]}"
    done

    for SERVICE in "${!SERVICES_AND_PORTS[@]}"; do
        echo "$SERVICE: ${SERVICES_AND_PORTS[$SERVICE]}" >> "$HOME/services_urls.txt"
    done
    echo "URLs saved to $HOME/services_urls.txt"

}

main
