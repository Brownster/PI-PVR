#!/bin/bash

# General Variables
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

# USB and Samba Variables
USB_DEVICE="/dev/sda1"           # Update this to match your USB device (use lsblk to verify)
MOUNT_POINT="/mnt/usbdrive"      # Where the drive will be mounted
SAMBA_CONFIG="/etc/samba/smb.conf" # Path to Samba configuration file

# Media folder names
MOVIES_FOLDER="Movies"       # Name of the folder for movies
TVSHOWS_FOLDER="TVShows"     # Name of the folder for TV shows

# Exit on error
set -e

# Install required dependencies
install_dependencies() {
    echo "Checking if Docker is already installed..."
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Installing Docker..."
        sudo apt update && sudo apt upgrade -y
        sudo apt install -y curl docker.io docker-compose
        echo "Docker installed successfully."
    else
        echo "Docker is already installed. Skipping installation."
    fi
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
    if docker network ls | grep -q "$CONTAINER_NETWORK"; then
        echo "Docker network '$CONTAINER_NETWORK' already exists."
    else
        docker network create "$CONTAINER_NETWORK"
        echo "Docker network '$CONTAINER_NETWORK' created."
    fi
}

# Create .env file for sensitive data
create_env_file() {
    echo "Creating .env file for sensitive data..."
    mkdir -p "$DOCKER_DIR"
    if [[ ! -f "$ENV_FILE" ]]; then
        read -p "Enter your PIA_USERNAME: " PIA_USERNAME
        read -s -p "Enter your PIA_PASSWORD: " PIA_PASSWORD
        echo ""
        read -p "Enter your TAILSCALE_AUTH_KEY (or press Enter to skip): " TAILSCALE_AUTH_KEY

        cat > "$ENV_FILE" <<EOF
PIA_USERNAME=$PIA_USERNAME
PIA_PASSWORD=$PIA_PASSWORD
TAILSCALE_AUTH_KEY=$TAILSCALE_AUTH_KEY
EOF
        echo ".env file created at $ENV_FILE."
        chmod 600 "$ENV_FILE"
    else
        echo ".env file already exists. Update credentials if necessary."
    fi
}

# Configure USB drive and Samba share
setup_usb_share() {
    echo "Setting up USB drive and Samba share..."

    # Dynamically detect the USB drive (8TB device)
    USB_DEVICE=$(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E '8T.+disk' | awk '{print "/dev/"$1}')
    if [[ -z "$USB_DEVICE" ]]; then
        echo "Error: Could not detect the USB drive. Ensure it is plugged in and formatted."
        exit 1
    fi
    echo "USB drive detected: $USB_DEVICE"

    # Create mount point if it doesn't exist
    if [[ ! -d "$MOUNT_POINT" ]]; then
        echo "Creating mount point at $MOUNT_POINT..."
        sudo mkdir -p "$MOUNT_POINT"
    fi

    # Mount the USB drive if not already mounted
    if ! mount | grep -q "$MOUNT_POINT"; then
        echo "Mounting USB drive..."
        sudo mount "$USB_DEVICE" "$MOUNT_POINT"
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to mount USB drive at $MOUNT_POINT. Check the device and try again."
            exit 1
        fi
    else
        echo "USB drive already mounted at $MOUNT_POINT."
    fi

    # Set permissions for media directories
    echo "Setting permissions for media directories..."
    sudo chmod -R 775 "$MOUNT_POINT"
    sudo chown -R $USER:$USER "$MOUNT_POINT"
    echo "Permissions set for $MOUNT_POINT."

    # Ask the user whether to create the media directories
    read -t 10 -p "Do you want to create the media directories ($MOVIES_FOLDER, $TVSHOWS_FOLDER) on the USB drive? [y/N]: " CREATE_DIRS
    CREATE_DIRS=${CREATE_DIRS:-N} # Default to 'N' if no input
    if [[ "$CREATE_DIRS" =~ ^[Yy]$ ]]; then
        echo "Creating media directories..."
        sudo mkdir -p "$MOUNT_POINT/$MOVIES_FOLDER"
        sudo mkdir -p "$MOUNT_POINT/$TVSHOWS_FOLDER"
        echo "Directories created: $MOVIES_FOLDER and $TVSHOWS_FOLDER."
    else
        echo "Skipping media directory creation."
    fi

    # Install Samba if not already installed
    if ! command -v smbd &> /dev/null; then
        echo "Installing Samba..."
        sudo apt update && sudo apt install -y samba
    fi

    # Backup the existing Samba config if not already backed up
    if [[ ! -f "$SAMBA_CONFIG.bak" ]]; then
        echo "Backing up existing Samba configuration..."
        sudo cp "$SAMBA_CONFIG" "$SAMBA_CONFIG.bak"
    fi

    # Add Samba share configuration if not already present
    if ! grep -q "\[$MOVIES_FOLDER\]" "$SAMBA_CONFIG"; then
        echo "Configuring Samba share..."
        sudo bash -c "cat >> $SAMBA_CONFIG" <<EOF

[$MOVIES_FOLDER]
   path = $MOUNT_POINT/$MOVIES_FOLDER
   browseable = yes
   read only = no
   guest ok = yes

[$TVSHOWS_FOLDER]
   path = $MOUNT_POINT/$TVSHOWS_FOLDER
   browseable = yes
   read only = no
   guest ok = yes
EOF
        # Restart Samba service
        echo "Restarting Samba service..."
        sudo systemctl restart smbd
    else
        echo "Samba share configuration already exists."
    fi

    echo "Samba share configured successfully!"
    echo "Local network shares available:"
    echo " - Movies: \\<Your Pi's IP>\\$MOVIES_FOLDER"
    echo " - TV Shows: \\<Your Pi's IP>\\$TVSHOWS_FOLDER"
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
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/jackett:/config
      - $MOUNT_POINT/Downloads:/downloads
    ports:
      - 9117:9117
    networks:
      - $CONTAINER_NETWORK
    restart: unless-stopped

  $SONARR_CONTAINER:
    image: $SONARR_IMAGE
    container_name: $SONARR_CONTAINER
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/sonarr:/config
      - $MOUNT_POINT/TVShows:/tv
      - $MOUNT_POINT/Downloads:/downloads
    ports:
      - 8989:8989
    networks:
      - $CONTAINER_NETWORK
    restart: unless-stopped

  $RADARR_CONTAINER:
    image: $RADARR_IMAGE
    container_name: $RADARR_CONTAINER
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/radarr:/config
      - $MOUNT_POINT/Movies:/movies
      - $MOUNT_POINT/Downloads:/downloads
    ports:
      - 7878:7878
    networks:
      - $CONTAINER_NETWORK
    restart: unless-stopped

  $TRANSMISSION_CONTAINER:
    image: $TRANSMISSION_IMAGE
    container_name: $TRANSMISSION_CONTAINER
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/transmission:/config
      - $MOUNT_POINT/Downloads:/downloads
    ports:
      - 9091:9091
    networks:
      - $CONTAINER_NETWORK
    restart: unless-stopped

  $NZBGET_CONTAINER:
    image: $NZBGET_IMAGE
    container_name: $NZBGET_CONTAINER
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/nzbget:/config
      - $MOUNT_POINT/Downloads:/downloads
    ports:
      - 6789:6789
    networks:
      - $CONTAINER_NETWORK
    restart: unless-stopped

  $WATCHTOWER_CONTAINER:
    image: $WATCHTOWER_IMAGE
    container_name: $WATCHTOWER_CONTAINER
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
    networks:
      - $CONTAINER_NETWORK
    restart: unless-stopped
EOF
    echo "Docker Compose file created at $DOCKER_DIR/docker-compose.yml"
}

# Preconfigure application settings
preconfigure_apps() {
    echo "Preconfiguring application settings..."

    # Jackett
    if [[ -f "$DOCKER_DIR/jackett/ServerConfig.json" ]]; then
        sudo sed -i 's|.*BasePath.*|  "BasePath": "/downloads",|' "$DOCKER_DIR/jackett/ServerConfig.json"
    fi

    # Sonarr
    if [[ -f "$DOCKER_DIR/sonarr/config.xml" ]]; then
        sudo sed -i 's|<RootFolderPath>.*</RootFolderPath>|<RootFolderPath>/mnt/usbdrive/TVShows</RootFolderPath>|' "$DOCKER_DIR/sonarr/config.xml"
        sudo sed -i 's|<DownloadClientPath>.*</DownloadClientPath>|<DownloadClientPath>/downloads</DownloadClientPath>|' "$DOCKER_DIR/sonarr/config.xml"
    fi

    # Radarr
    if [[ -f "$DOCKER_DIR/radarr/config.xml" ]]; then
        sudo sed -i 's|<RootFolderPath>.*</RootFolderPath>|<RootFolderPath>/mnt/usbdrive/Movies</RootFolderPath>|' "$DOCKER_DIR/radarr/config.xml"
        sudo sed -i 's|<DownloadClientPath>.*</DownloadClientPath>|<DownloadClientPath>/downloads</DownloadClientPath>|' "$DOCKER_DIR/radarr/config.xml"
    fi

    # Transmission
    if [[ -f "$DOCKER_DIR/transmission/settings.json" ]]; then
        sudo sed -i 's|"download-dir": ".*"|"download-dir": "/downloads"|' "$DOCKER_DIR/transmission/settings.json"
        sudo sed -i 's|"rpc-username": ".*"|"rpc-username": "your_username"|' "$DOCKER_DIR/transmission/settings.json"
        sudo sed -i 's|"rpc-password": ".*"|"rpc-password": "your_password"|' "$DOCKER_DIR/transmission/settings.json"
    fi

    # NZBGet
    if [[ -f "$DOCKER_DIR/nzbget/nzbget.conf" ]]; then
        sudo sed -i 's|MainDir=.*|MainDir=/downloads|' "$DOCKER_DIR/nzbget/nzbget.conf"
        sudo sed -i 's|DestDir=.*|DestDir=/mnt/usbdrive/Movies|' "$DOCKER_DIR/nzbget/nzbget.conf"
    fi

    # Restart affected containers to apply changes
    echo "Restarting affected Docker containers to apply changes..."
    docker-compose -f "$DOCKER_DIR/docker-compose.yml" restart $JACKETT_CONTAINER $SONARR_CONTAINER $RADARR_CONTAINER $TRANSMISSION_CONTAINER $NZBGET_CONTAINER
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
    echo "Starting setup..."
    install_dependencies
    setup_tailscale
    setup_docker_network
    create_env_file
    create_docker_compose
    setup_usb_share
    deploy_docker_compose
    preconfigure_apps
    echo "Setup complete. Update the .env file with credentials if not already done."
}

main
