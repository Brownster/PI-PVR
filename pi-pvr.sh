#!/bin/bash
# Server Variables
SHARE_METHOD=""
SERVER_IP=$(hostname -I | awk '{print $1}')
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

# Samba Variable
SAMBA_CONFIG="/etc/samba/smb.conf" # Path to Samba configuration file

# Media folder names
MOVIES_FOLDER="Movies"       # Name of the folder for movies
TVSHOWS_FOLDER="TVShows"     # Name of the folder for TV shows

# Exit on error
set -euo pipefail

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
        sudo tailscale up --accept-routes=false
    else
        sudo tailscale up --accept-routes=false --authkey="$TAILSCALE_AUTH_KEY"
    fi

    echo "Tailscale is running."
    echo "Access your server using its Tailscale IP: $(tailscale ip -4)"
    echo "Manage devices at https://login.tailscale.com."
}

setup_pia_vpn() {
    echo "Setting up PIA WireGuard VPN..."

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

    # Install required dependencies, including curl and jq
    echo "Installing dependencies..."
    sudo apt update
    sudo apt install -y curl

    # Generate token using PIA credentials
    echo "Generating PIA token..."

    # Make sure curl and jq are installed
    for cmd in curl jq; do
        if ! command -v "$cmd" >/dev/null; then
            echo "$cmd could not be found. Please install $cmd."
            exit 1
        fi
    done

    # Generate the token by sending a POST request to the PIA API
    generateTokenResponse=$(curl -s --location --request POST \
        'https://www.privateinternetaccess.com/api/client/v2/token' \
        --form "username=$PIA_USERNAME" \
        --form "password=$PIA_PASSWORD")

    # Check if the response contains a token
    token=$(echo "$generateTokenResponse" | jq -r '.token')
    if [[ -z "$token" || "$token" == "null" ]]; then
        echo "Error: Could not authenticate with the login credentials provided!"
        exit 1
    fi

    # Create a timestamp for when the token will expire (24 hours from now)
    tokenExpiration=$(date +"%c" --date='1 day')
    tokenLocation="/opt/piavpn-manual/token"

    # Save the token to a file for later use
    echo "$token" > "$tokenLocation" || exit 1
    echo "$tokenExpiration" >> "$tokenLocation"
    echo "Token generated successfully."
    echo "This token will expire in 24 hours, on $tokenExpiration."

    # Get the server information
    echo "Requesting server information..."
    SERVER_INFO=$(curl -s "https://serverlist.piaservers.net/vpninfo/servers/v6")

    # Extract the information for the desired location (Netherlands, Amsterdam)
    REGION="nl-amsterdam.privacy.network"
    server_ip=$(echo "$SERVER_INFO" | jq -r --arg region "$REGION" '.regions[] | select(.id == $region) | .servers.wg[0].ip')

    if [[ -z "$server_ip" || "$server_ip" == "null" ]]; then
        echo "Error: Could not retrieve server information for region: $REGION"
        exit 1
    fi

    echo "Server IP for region $REGION is $server_ip."

    # Generate the WireGuard configuration
    WG_CONFIG=$(curl -s "https://10.0.0.1:1337/addKey" --insecure \
        -d "token=$token" -d "server_ip=$server_ip")

    if [[ -z "$WG_CONFIG" || "$WG_CONFIG" == "null" ]]; then
        echo "Error: Failed to create WireGuard configuration."
        exit 1
    fi

    # Save the WireGuard configuration to wg0.conf
    WG_CONFIG_FILE="$DOCKER_DIR/manual-connections/wg0.conf"
    mkdir -p "$(dirname "$WG_CONFIG_FILE")"
    echo "$WG_CONFIG" > "$WG_CONFIG_FILE"
    chmod 600 "$WG_CONFIG_FILE"
    echo "WireGuard configuration saved to $WG_CONFIG_FILE."
}




#choose smb or nfs (smb if using windows devices to connect)
choose_sharing_method() {
    echo "Choose your preferred file sharing method:"
    echo "1. Samba (Best for cross-platform: Windows, macOS, Linux)"
    echo "2. NFS (Best for Linux-only environments)"
    read -r -p "Enter the number (1 or 2): " SHARE_METHOD

    if [[ "$SHARE_METHOD" == "1" ]]; then
        setup_usb_and_samba
    elif [[ "$SHARE_METHOD" == "2" ]]; then
        setup_usb_and_nfs
    else
        echo "Invalid selection. Defaulting to Samba."
        SHARE_METHOD="1"
        setup_usb_and_samba
    fi

    SERVER_IP=$(hostname -I | awk '{print $1}') # Ensure SERVER_IP is set here for global use
}



# Configure USB drive and Samba share
setup_usb_and_samba() {
    echo "Detecting USB drives..."

    # List available partitions, assuming they are NTFS formatted
    USB_DRIVES=$(lsblk -o NAME,SIZE,TYPE | awk '/part/ {print "/dev/"$1, $2}' | sed 's/[└├─]//g')

    if [[ -z "$USB_DRIVES" ]]; then
        echo "No USB drives detected. Please ensure they are connected and retry."
        exit 1
    fi

    echo "Available USB drives:"
    echo "$USB_DRIVES" | nl
    read -r -p "Select the drive number for storage: " STORAGE_SELECTION
    STORAGE_DRIVE=$(echo "$USB_DRIVES" | sed -n "${STORAGE_SELECTION}p" | awk '{print $1}')

    read -r -p "Do you want to use the same drive for downloads? (y/n): " SAME_DRIVE
    if [[ "$SAME_DRIVE" =~ ^[Yy]$ ]]; then
        DOWNLOAD_DRIVE=$STORAGE_DRIVE
    else
        echo "Available USB drives:"
        echo "$USB_DRIVES" | nl
        read -r -p "Select the drive number for downloads: " DOWNLOAD_SELECTION
        DOWNLOAD_DRIVE=$(echo "$USB_DRIVES" | sed -n "${DOWNLOAD_SELECTION}p" | awk '{print $1}')
    fi

    # Mount drives (assuming NTFS filesystem)
    STORAGE_MOUNT="/mnt/storage"
    DOWNLOAD_MOUNT="/mnt/downloads"

    echo "Mounting $STORAGE_DRIVE to $STORAGE_MOUNT..."
    sudo mkdir -p "$STORAGE_MOUNT"
    sudo apt install -y ntfs-3g
    sudo mount -t ntfs-3g "$STORAGE_DRIVE" "$STORAGE_MOUNT"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to mount $STORAGE_DRIVE. Please check the drive and try again."
        exit 1
    fi

    if [[ "$SAME_DRIVE" =~ ^[Nn]$ ]]; then
        echo "Mounting $DOWNLOAD_DRIVE to $DOWNLOAD_MOUNT..."
        sudo mkdir -p "$DOWNLOAD_MOUNT"
        sudo mount -t ntfs-3g "$DOWNLOAD_DRIVE" "$DOWNLOAD_MOUNT"
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to mount $DOWNLOAD_DRIVE. Please check the drive and try again."
            exit 1
        fi
    fi

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
        read -r -p "TVShows directory not found. Do you want to create it? (y/n): " CREATE_TVSHOWS
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

    # Install Samba if not already installed
    if ! command -v smbd &> /dev/null; then
        echo "Samba is not installed. Installing Samba..."
        sudo apt-get install -y samba samba-common-bin
    fi

    # Configure Samba
    echo "Configuring Samba..."
    SAMBA_CONFIG="/etc/samba/smb.conf"
    if [[ -f "$SAMBA_CONFIG" ]]; then
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
    else
        echo "Error: Samba configuration file not found at $SAMBA_CONFIG. Please ensure Samba is properly installed."
        exit 1
    fi

    echo "Configuration complete."
    echo "Storage Drive Mounted: $STORAGE_MOUNT"
    echo "Download Drive Mounted: $DOWNLOAD_MOUNT"
    echo "Samba Shares:"
    printf '  \\%s\\Movies\n' "$SERVER_IP"
    printf '  \\%s\\TVShows\n' "$SERVER_IP"
    printf '  \\%s\\Downloads\n' "$SERVER_IP"
}

setup_usb_and_nfs() {
    echo "Installing necessary NFS packages..."
    sudo apt-get install -y nfs-kernel-server

    echo "Detecting USB drives..."
    USB_DRIVES=$(lsblk -o NAME,SIZE,TYPE | awk '/part/ {print "/dev/"$1, $2}' | sed 's/[└├─]//g')
    
    if [[ -z "$USB_DRIVES" ]]; then
        echo "No USB drives detected. Please ensure they are connected and retry."
        exit 1
    fi

    echo "Available USB drives:"
    echo "$USB_DRIVES" | nl
    read -r -p "Select the drive number for storage: " STORAGE_SELECTION
    STORAGE_DRIVE=$(echo "$USB_DRIVES" | sed -n "${STORAGE_SELECTION}p" | awk '{print $1}')

    read -r -p "Do you want to use the same drive for downloads? (y/n): " SAME_DRIVE
    if [[ "$SAME_DRIVE" =~ ^[Yy]$ ]]; then
        DOWNLOAD_DRIVE=$STORAGE_DRIVE
    else
        echo "Available USB drives:"
        echo "$USB_DRIVES" | nl
        read -r -p "Select the drive number for downloads: " DOWNLOAD_SELECTION
        DOWNLOAD_DRIVE=$(echo "$USB_DRIVES" | sed -n "${DOWNLOAD_SELECTION}p" | awk '{print $1}')
    fi

    # Mount drives (assuming NTFS filesystem)
    STORAGE_MOUNT="/mnt/storage"
    DOWNLOAD_MOUNT="/mnt/downloads"

    echo "Mounting $STORAGE_DRIVE to $STORAGE_MOUNT..."
    sudo mkdir -p "$STORAGE_MOUNT"
    sudo apt install -y ntfs-3g
    sudo mount -t ntfs-3g "$STORAGE_DRIVE" "$STORAGE_MOUNT"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to mount $STORAGE_DRIVE. Please check the drive and try again."
        exit 1
    fi

    if [[ "$SAME_DRIVE" =~ ^[Nn]$ ]]; then
        echo "Mounting $DOWNLOAD_DRIVE to $DOWNLOAD_MOUNT..."
        sudo mkdir -p "$DOWNLOAD_MOUNT"
        sudo mount -t ntfs-3g "$DOWNLOAD_DRIVE" "$DOWNLOAD_MOUNT"
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to mount $DOWNLOAD_DRIVE. Please check the drive and try again."
            exit 1
        fi
    fi

    # Detect and create media directories
    MOVIES_DIR="$STORAGE_MOUNT/Movies"
    TVSHOWS_DIR="$STORAGE_MOUNT/TVShows"

    if [[ ! -d "$MOVIES_DIR" ]]; then
        read -r -p "Movies directory not found. Do you want to create it? (y/n): " CREATE_MOVIES
        if [[ "$CREATE_MOVIES" =~ ^[Yy]$ ]]; then
            echo "Creating Movies directory..."
            sudo mkdir -p "$MOVIES_DIR"
        else
            echo "Skipping Movies directory creation."
        fi
    fi

    if [[ ! -d "$TVSHOWS_DIR" ]]; then
        read -r -p "TVShows directory not found. Do you want to create it? (y/n): " CREATE_TVSHOWS
        if [[ "$CREATE_TVSHOWS" =~ ^[Yy]$ ]]; then
            echo "Creating TVShows directory..."
            sudo mkdir -p "$TVSHOWS_DIR"
        else
            echo "Skipping TVShows directory creation."
        fi
    fi

    # Update /etc/exports for NFS
    EXPORTS_FILE="/etc/exports"
    echo "Setting up NFS share..."
    
    # Add storage directory if not already in exports
    if ! grep -q "$STORAGE_MOUNT" "$EXPORTS_FILE"; then
        echo "$STORAGE_MOUNT *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a "$EXPORTS_FILE"
    fi

    # Add download directory if not already in exports
    if ! grep -q "$DOWNLOAD_MOUNT" "$EXPORTS_FILE"; then
        echo "$DOWNLOAD_MOUNT *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a "$EXPORTS_FILE"
    fi

    echo "Exporting directories for NFS..."
    sudo exportfs -ra

    echo "Restarting NFS server..."
    sudo systemctl restart nfs-kernel-server

    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo "Configuration complete."
    echo "NFS Shares available at:"
    echo "  $SERVER_IP:$STORAGE_MOUNT"
    echo "  $SERVER_IP:$DOWNLOAD_MOUNT"
}


# Create Docker Compose file
create_docker_compose() {
    echo "Creating Docker Compose file..."
    cat > "$DOCKER_DIR/docker-compose.yml" <<EOF
version: "3.8"
services:
  vpn:
    image: qmcgaw/gluetun:latest
    container_name: vpn
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - $DOCKER_DIR/manual-connections/wg0.conf:/gluetun/wireguard/wg0.conf:ro
    environment:
      - VPN_SERVICE_PROVIDER=custom
      - VPN_TYPE=wireguard
    healthcheck:
      test: curl --fail http://localhost:8000 || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped
    ports:
      - 9117:9117   # Jackett
      - 8989:8989   # Sonarr
      - 7878:7878   # Radarr
      - 9091:9091   # Transmission
      - 6789:6789   # NZBGet
    networks:
      - vpn_network

  jackett:
    image: linuxserver/jackett:latest
    container_name: jackett
    network_mode: "service:vpn"
    environment:
      - TZ=Europe/Berlin
    volumes:
      - /home/holly/docker/jackett:/config
      - /mnt/downloads:/downloads
    restart: unless-stopped

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    network_mode: "service:vpn"
    environment:
      - TZ=Europe/Berlin
    volumes:
      - /home/holly/docker/sonarr:/config
      - /mnt/storage/TVShows:/tv
      - /mnt/downloads:/downloads
    restart: unless-stopped

  radarr:
    image: linuxserver/radarr:latest
    container_name: radarr
    network_mode: "service:vpn"
    environment:
      - TZ=Europe/Berlin
    volumes:
      - /home/holly/docker/radarr:/config
      - /mnt/storage/Movies:/movies
      - /mnt/downloads:/downloads
    restart: unless-stopped

  transmission:
    image: linuxserver/transmission:latest
    container_name: transmission
    network_mode: "service:vpn"
    environment:
      - TZ=Europe/Berlin
    volumes:
      - /home/holly/docker/transmission:/config
      - /mnt/downloads:/downloads
    restart: unless-stopped

  nzbget:
    image: linuxserver/nzbget:latest
    container_name: nzbget
    network_mode: "service:vpn"
    environment:
      - TZ=Europe/Berlin
      - PUID=1000
      - PGID=1000
    volumes:
      - /home/holly/docker/nzbget:/config
      - /mnt/downloads/incomplete:/incomplete
      - /mnt/downloads/complete:/complete
    restart: unless-stopped

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE="0 3 * * *" # Run daily at 3 AM
    restart: unless-stopped
    networks:
      - vpn_network

networks:
  vpn_network:
    driver: bridge
EOF
    echo "Docker Compose file created at $DOCKER_DIR/docker-compose.yml"
}


    # Install required dependencies, including git
    echo "Installing dependencies..."
    sudo apt update
    sudo apt install -y curl jq wireguard-tools git
# Install required dependencies
install_dependencies() {
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

    echo "Installing other required dependencies: curl, jq, wireguard-tools, git..."
    sudo apt-get install -y curl jq wireguard-tools git

    echo "Verifying Docker installation..."
    sudo docker run hello-world

    echo "All dependencies installed successfully."
}


# Set up Docker network for VPN containers
setup_docker_network() {
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
    fi
}


# Deploy Docker Compose stack
deploy_docker_compose() {
    echo "Deploying Docker Compose stack..."
    sudo usermod -aG docker "$USER"
    #newgrp docker
    if ! docker compose --env-file "$ENV_FILE" -f "$DOCKER_DIR/docker-compose.yml" up -d; then
        echo "Error: Failed to deploy Docker Compose stack."
        exit 1
    fi
    echo "Docker Compose stack deployed successfully."
}

setup_mount_and_docker_start() {
    echo "Configuring drives to mount at boot and Docker to start afterwards..."

    # Variables for mount points and device paths
    STORAGE_MOUNT="/mnt/storage"
    DOWNLOAD_MOUNT="/mnt/downloads"

    # Get device UUIDs for fstab
    STORAGE_UUID=$(blkid -s UUID -o value "$(findmnt -nT "$STORAGE_MOUNT" | awk '{print $2}')")
    DOWNLOAD_UUID=$(blkid -s UUID -o value "$(findmnt -nT "$DOWNLOAD_MOUNT" | awk '{print $2}')")

    if [[ -z "$STORAGE_UUID" || -z "$DOWNLOAD_UUID" ]]; then
        echo "Error: Could not determine UUIDs for storage or download drives."
        exit 1
    fi

    # Update /etc/fstab for persistent mount
    echo "Updating /etc/fstab..."
    sudo bash -c "cat >> /etc/fstab" <<EOF
UUID=$STORAGE_UUID $STORAGE_MOUNT ext4 defaults 0 2
UUID=$DOWNLOAD_UUID $DOWNLOAD_MOUNT ext4 defaults 0 2
EOF

    # Test the fstab changes
    sudo mount -a
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to mount drives. Please check /etc/fstab."
        exit 1
    fi

    echo "Drives are configured to mount at boot."

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
DOCKER_COMPOSE_FILE="$HOME/docker/docker-compose.yml"

# Wait until mounts are ready
until mountpoint -q "$STORAGE_MOUNT" && mountpoint -q "$DOWNLOAD_MOUNT"; do
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


# Main setup function
main() {
    echo "Starting setup..."
    create_env_file
    setup_tailscale
    install_dependencies
    setup_pia_vpn
    create_docker_compose
    choose_sharing_method
    setup_docker_network
    deploy_docker_compose
    setup_mount_and_docker_start
    echo "Setup complete. Update the .env file with credentials if not already done."
    echo "Setup Summary:"
    echo "Docker services are running:"

    # Define a list of apps and their ports
    declare -A SERVICES_AND_PORTS=(
        ["VPN"]="--"
        ["Jackett"]="9117"
        ["Sonarr"]="8989"
        ["Radarr"]="7878"
        ["Transmission"]="9091"
        ["NZBGet"]="6789"
        ["Watchtower"]="Auto-Updater"
    )

    # Loop through the services and display their ports
    for SERVICE in "${!SERVICES_AND_PORTS[@]}"; do
        echo "  - $SERVICE (Port: ${SERVICES_AND_PORTS[$SERVICE]})"
    done

    echo "File shares available:"
    if [[ "$SHARE_METHOD" == "1" ]]; then
        echo "  Samba Shares:"
        printf '    \\\\%s\\\\Movies\n' "$SERVER_IP"
        printf '    \\\\%s\\\\TVShows\n' "$SERVER_IP"
        printf '    \\\\%s\\\\Downloads\n' "$SERVER_IP"

    elif [[ "$SHARE_METHOD" == "2" ]]; then
        echo "  NFS Shares:"
        echo "    $SERVER_IP:$STORAGE_DIR"
        echo "    $SERVER_IP:$DOWNLOAD_DIR"
    fi

}

main
