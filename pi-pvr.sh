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


# Configure USB drive and Samba share
setup_usb_and_samba() {
    echo "Detecting USB drives..."
    USB_DRIVES=$(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'disk' | awk '{print "/dev/"$1, $2}')
    
    if [[ -z "$USB_DRIVES" ]]; then
        echo "No USB drives detected. Please ensure they are connected and retry."
        exit 1
    fi

    echo "Available USB drives:"
    echo "$USB_DRIVES" | nl
    read -p "Select the drive number for storage: " STORAGE_SELECTION
    STORAGE_DRIVE=$(echo "$USB_DRIVES" | sed -n "${STORAGE_SELECTION}p" | awk '{print $1}')
    
    read -p "Do you want to use the same drive for downloads? (y/n): " SAME_DRIVE
    if [[ "$SAME_DRIVE" =~ ^[Yy]$ ]]; then
        DOWNLOAD_DRIVE=$STORAGE_DRIVE
    else
        echo "Available USB drives:"
        echo "$USB_DRIVES" | nl
        read -p "Select the drive number for downloads: " DOWNLOAD_SELECTION
        DOWNLOAD_DRIVE=$(echo "$USB_DRIVES" | sed -n "${DOWNLOAD_SELECTION}p" | awk '{print $1}')
    fi

    # Mount drives
    STORAGE_MOUNT="/mnt/storage"
    DOWNLOAD_MOUNT="/mnt/downloads"

    echo "Mounting $STORAGE_DRIVE to $STORAGE_MOUNT..."
    sudo mkdir -p "$STORAGE_MOUNT"
    sudo mount "$STORAGE_DRIVE" "$STORAGE_MOUNT"
    echo "Mounting $DOWNLOAD_DRIVE to $DOWNLOAD_MOUNT..."
    sudo mkdir -p "$DOWNLOAD_MOUNT"
    sudo mount "$DOWNLOAD_DRIVE" "$DOWNLOAD_MOUNT"

    # Detect and create media directories
    MOVIES_DIR="$STORAGE_MOUNT/Movies"
    TVSHOWS_DIR="$STORAGE_MOUNT/TVShows"

    if [[ -d "$MOVIES_DIR" ]]; then
        echo "Movies directory already exists at $MOVIES_DIR. Skipping creation."
    else
        read -p "Movies directory not found. Do you want to create it? (y/n): " CREATE_MOVIES
        if [[ "$CREATE_MOVIES" =~ ^[Yy]$ ]]; then
            echo "Creating Movies directory..."
            sudo mkdir -p "$MOVIES_DIR"
        else
            echo "Skipping Movies directory creation."
        fi
    fi

    if [[ -d "$TVSHOWS_DIR" ]]; then
        echo "TVShows directory already exists at $TVSHOWS_DIR. Skipping creation."
    else
        read -p "TVShows directory not found. Do you want to create it? (y/n): " CREATE_TVSHOWS
        if [[ "$CREATE_TVSHOWS" =~ ^[Yy]$ ]]; then
            echo "Creating TVShows directory..."
            sudo mkdir -p "$TVSHOWS_DIR"
        else
            echo "Skipping TVShows directory creation."
        fi
    fi

    # Set permissions for media directories
    echo "Setting permissions for media directories..."
    sudo chmod -R 775 "$STORAGE_MOUNT"
    sudo chown -R $USER:$USER "$STORAGE_MOUNT"

    # Configure Samba
    echo "Configuring Samba..."
    SAMBA_CONFIG="/etc/samba/smb.conf"
    if [[ ! -f "$SAMBA_CONFIG.bak" ]]; then
        echo "Backing up existing Samba configuration..."
        sudo cp "$SAMBA_CONFIG" "$SAMBA_CONFIG.bak"
    fi

    if ! grep -q "\[Movies\]" "$SAMBA_CONFIG"; then
        echo "Adding Samba share for Movies and TVShows..."
        sudo bash -c "cat >> $SAMBA_CONFIG" <<EOF

[Movies]
   path = $MOVIES_DIR
   browseable = yes
   read only = no
   guest ok = yes

[TVShows]
   path = $TVSHOWS_DIR
   browseable = yes
   read only = no
   guest ok = yes

[Downloads]
   path = $DOWNLOAD_MOUNT
   browseable = yes
   read only = no
   guest ok = yes
EOF
        sudo systemctl restart smbd
        echo "Samba shares configured and service restarted."
    else
        echo "Samba shares already exist. Skipping."
    fi

# Get the server's IP address dynamically and print samba shares.
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo "Configuration complete."
    echo "Storage Drive Mounted: $STORAGE_MOUNT"
    echo "Download Drive Mounted: $DOWNLOAD_MOUNT"
    echo "Samba Shares:"
    echo "  \\$SERVER_IP\\Movies"
    echo "  \\$SERVER_IP\\TVShows"
    echo "  \\$SERVER_IP\\Downloads"
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
    ports:
      - 9117:9117 # Jackett
      - 8989:8989 # Sonarr
      - 7878:7878 # Radarr
      - 9091:9091 # Transmission
      - 6789:6789 # NZBGet
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
    network_mode: "service:$VPN_CONTAINER"
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/jackett:/config
      - $MOUNT_POINT/Downloads:/downloads
    restart: unless-stopped

  $SONARR_CONTAINER:
    image: $SONARR_IMAGE
    container_name: $SONARR_CONTAINER
    network_mode: "service:$VPN_CONTAINER"
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/sonarr:/config
      - $MOUNT_POINT/TVShows:/tv
      - $MOUNT_POINT/Downloads:/downloads
    restart: unless-stopped

  $RADARR_CONTAINER:
    image: $RADARR_IMAGE
    container_name: $RADARR_CONTAINER
    network_mode: "service:$VPN_CONTAINER"
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/radarr:/config
      - $MOUNT_POINT/Movies:/movies
      - $MOUNT_POINT/Downloads:/downloads
    restart: unless-stopped

  $TRANSMISSION_CONTAINER:
    image: $TRANSMISSION_IMAGE
    container_name: $TRANSMISSION_CONTAINER
    network_mode: "service:$VPN_CONTAINER"
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/transmission:/config
      - $MOUNT_POINT/Downloads:/downloads
    restart: unless-stopped

  $NZBGET_CONTAINER:
    image: $NZBGET_IMAGE
    container_name: $NZBGET_CONTAINER
    network_mode: "service:$VPN_CONTAINER"
    environment:
      - TZ=$TIMEZONE
    volumes:
      - $DOCKER_DIR/nzbget:/config
      - $MOUNT_POINT/Downloads:/downloads
    restart: unless-stopped

  $WATCHTOWER_CONTAINER:
    image: $WATCHTOWER_IMAGE
    container_name: $WATCHTOWER_CONTAINER
    network_mode: "service:$VPN_CONTAINER"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE="0 3 * * *" # Run daily at 3 AM
    restart: unless-stopped

networks:
  $CONTAINER_NETWORK:
    driver: bridge
EOF
    echo "Docker Compose file created at $DOCKER_DIR/docker-compose.yml"
}

# install docker and anything else needed
install_dependencies() {
    echo "Uninstalling any conflicting Docker packages..."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        sudo apt-get remove -y \$pkg
    done

    echo "Adding Docker's official GPG key and repository..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    \$(. /etc/os-release && echo "\$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update

    echo "Installing Docker Engine, Docker Compose, and related packages..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Verifying Docker installation..."
    sudo docker run hello-world

    echo "Docker installed successfully."
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
    create_env_file
    setup_tailscale
    create_docker_compose
    setup_usb_and_samba
    install_dependencies
    setup_docker_network
    deploy_docker_compose
    #preconfigure_apps
    echo "Setup complete. Update the .env file with credentials if not already done."
}

main
