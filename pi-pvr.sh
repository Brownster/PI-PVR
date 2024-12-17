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
tailscale_install_success=0
PIA_SETUP_SUCCESS=0
SHARE_SETUP_SUCCESS=0
docker_install_success=0
pia_vpn_setup_success=0
docker_compose_success=0
EOF
        echo ".env file created at $ENV_FILE."
        chmod 600 "$ENV_FILE"
    else
        echo ".env file already exists. Update credentials if necessary."
    fi
}

# Function to update /etc/fstab with the new mount point
update_fstab() {
    local mount_point="$1"
    local device="$2"

    # Get the UUID of the device
    local uuid=$(blkid -s UUID -o value "$device")
    if [[ -z "$uuid" ]]; then
        echo "Error: Could not retrieve UUID for device $device."
        exit 1
    fi

    # Check if the mount point is already in /etc/fstab
    if grep -q "$mount_point" /etc/fstab; then
        echo "Mount point $mount_point already exists in /etc/fstab. Skipping."
    else
        echo "Adding $mount_point to /etc/fstab..."
        echo "UUID=$uuid $mount_point auto defaults 0 2" | sudo tee -a /etc/fstab > /dev/null
    fi
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
    GLUETUN_DIR="$DOCKER_DIR/gluetun"
    echo "Creating Gluetun configuration directory at $GLUETUN_DIR..."
    mkdir -p "$GLUETUN_DIR"

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


#choose smb or nfs (smb if using windows devices to connect)
choose_sharing_method() {
    if [[ "$SHARE_SETUP_SUCCESS" == "1" ]]; then
        echo "Network shares already setup. Skipping."
        return
    fi    

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

    # List available partitions
    USB_DRIVES=$(lsblk -o NAME,SIZE,TYPE,FSTYPE | awk '/part/ {print "/dev/"$1, $2, $4}' | sed 's/[└├─]//g')

    if [[ -z "$USB_DRIVES" ]]; then
        echo "No USB drives detected. Please ensure they are connected and retry."
        exit 1
    fi

    # Display USB drives and prompt for storage drive
    echo "Available USB drives:"
    echo "$USB_DRIVES" | nl
    read -r -p "Select the drive number for storage (TV Shows and Movies): " STORAGE_SELECTION
    STORAGE_DRIVE=$(echo "$USB_DRIVES" | sed -n "${STORAGE_SELECTION}p" | awk '{print $1}')
    STORAGE_FS=$(echo "$USB_DRIVES" | sed -n "${STORAGE_SELECTION}p" | awk '{print $3}')
    
    # Define storage mount point before case
    STORAGE_MOUNT="/mnt/storage"

    # Option for downloads directory
    echo "Do you want to:"
    echo "1. Use the same drive for downloads."
    echo "2. Use a different USB drive for downloads."
    echo "3. Explicitly specify a path for downloads (e.g., internal storage)."
    read -r -p "Enter your choice (1/2/3): " DOWNLOAD_CHOICE

case "$DOWNLOAD_CHOICE" in
    1)
        DOWNLOAD_DRIVE=$STORAGE_DRIVE
        DOWNLOAD_FS=$STORAGE_FS
        DOWNLOAD_MOUNT="$STORAGE_MOUNT/downloads"  # Explicitly set the downloads mount path
        ;;
    2)
        echo "Available USB drives:"
        echo "$USB_DRIVES" | nl
        read -r -p "Select the drive number for downloads: " DOWNLOAD_SELECTION
        DOWNLOAD_DRIVE=$(echo "$USB_DRIVES" | sed -n "${DOWNLOAD_SELECTION}p" | awk '{print $1}')
        DOWNLOAD_FS=$(echo "$USB_DRIVES" | sed -n "${DOWNLOAD_SELECTION}p" | awk '{print $3}')
        DOWNLOAD_MOUNT="/mnt/downloads"  # Default path for a different drive
        ;;
    3)
        read -r -p "Enter the explicit path for downloads (e.g., /home/username/Downloads): " DOWNLOAD_MOUNT
        ;;
    *)
        echo "Invalid choice. Defaulting to the same drive for downloads."
        DOWNLOAD_DRIVE=$STORAGE_DRIVE
        DOWNLOAD_FS=$STORAGE_FS
        DOWNLOAD_MOUNT="$STORAGE_MOUNT/downloads"  # Default path if invalid input
        ;;
esac

    # Define mount points
    STORAGE_MOUNT="/mnt/storage"
    if [[ -z "$DOWNLOAD_MOUNT" ]]; then
        DOWNLOAD_MOUNT="/mnt/downloads"
    fi

    # Mount storage drive
    echo "Mounting $STORAGE_DRIVE to $STORAGE_MOUNT..."
    sudo mkdir -p "$STORAGE_MOUNT"
    if [[ "$STORAGE_FS" == "ntfs" ]]; then
        sudo mount -t ntfs-3g "$STORAGE_DRIVE" "$STORAGE_MOUNT"
    else
        sudo mount "$STORAGE_DRIVE" "$STORAGE_MOUNT"
    fi
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to mount $STORAGE_DRIVE. Please check the drive and try again."
        exit 1
    fi

    # Update fstab for storage drive
    update_fstab "$STORAGE_MOUNT" "$STORAGE_DRIVE"

    # Mount download drive or validate path
    if [[ "$DOWNLOAD_CHOICE" == "2" ]]; then
        echo "Mounting $DOWNLOAD_DRIVE to $DOWNLOAD_MOUNT..."
        sudo mkdir -p "$DOWNLOAD_MOUNT"
        if [[ "$DOWNLOAD_FS" == "ntfs" ]]; then
            sudo mount -t ntfs-3g "$DOWNLOAD_DRIVE" "$DOWNLOAD_MOUNT"
        else
            sudo mount "$DOWNLOAD_DRIVE" "$DOWNLOAD_MOUNT"
        fi
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to mount $DOWNLOAD_DRIVE. Please check the drive and try again."
            exit 1
        fi
        update_fstab "$DOWNLOAD_MOUNT" "$DOWNLOAD_DRIVE"
    else
        # Verify the explicit path exists
        sudo mkdir -p "$DOWNLOAD_MOUNT"
    fi

    # Detect and create media directories
    MOVIES_DIR="$STORAGE_MOUNT/Movies"
    TVSHOWS_DIR="$STORAGE_MOUNT/TVShows"

    for DIR in "$MOVIES_DIR" "$TVSHOWS_DIR"; do
        if [[ ! -d "$DIR" ]]; then
            echo "Creating directory $DIR..."
            sudo mkdir -p "$DIR"
        fi
    done

    # Set permissions for storage and downloads
    echo "Setting permissions..."
    sudo chmod -R 775 "$STORAGE_MOUNT" "$DOWNLOAD_MOUNT"
    sudo chown -R "$USER:$USER" "$STORAGE_MOUNT" "$DOWNLOAD_MOUNT"

    # Install Samba and configure shares
    echo "Configuring Samba..."
    if ! command -v smbd &> /dev/null; then
        sudo apt-get install -y samba samba-common-bin
    fi

    # Add shares
    if ! grep -q "\[Downloads\]" "$SAMBA_CONFIG"; then
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
    fi

    echo "Configuration complete."
    echo "Storage Drive Mounted: $STORAGE_MOUNT"
    echo "Download Location: $DOWNLOAD_MOUNT"
    echo "Samba Shares:"
    printf '  \\\\%s\\Movies\n' "$SERVER_IP"
    printf '  \\\\%s\\TVShows\n' "$SERVER_IP"
    printf '  \\\\%s\\Downloads\n' "$SERVER_IP"

    # Mark success
    sed -i 's/SHARE_SETUP_SUCCESS=0/SHARE_SETUP_SUCCESS=1/' "$ENV_FILE"
}


setup_usb_and_nfs() {
    echo "Installing necessary NFS packages..."
    sudo apt-get install -y nfs-kernel-server

    echo "Detecting USB drives..."
    USB_DRIVES=$(lsblk -o NAME,SIZE,TYPE,FSTYPE | awk '/part/ {print "/dev/"$1, $2, $4}' | sed 's/[└├─]//g')

    if [[ -z "$USB_DRIVES" ]]; then
        echo "No USB drives detected. Please ensure they are connected and retry."
        exit 1
    fi

    echo "Available USB drives:"
    echo "$USB_DRIVES" | nl
    read -r -p "Select the drive number for storage: " STORAGE_SELECTION
    STORAGE_DRIVE=$(echo "$USB_DRIVES" | sed -n "${STORAGE_SELECTION}p" | awk '{print $1}')
    STORAGE_FS=$(echo "$USB_DRIVES" | sed -n "${STORAGE_SELECTION}p" | awk '{print $3}')

    read -r -p "Do you want to use the same drive for downloads? (y/n): " SAME_DRIVE
    if [[ "$SAME_DRIVE" =~ ^[Yy]$ ]]; then
        DOWNLOAD_DRIVE=$STORAGE_DRIVE
        DOWNLOAD_FS=$STORAGE_FS
    else
        echo "Available USB drives:"
        echo "$USB_DRIVES" | nl
        read -r -p "Select the drive number for downloads: " DOWNLOAD_SELECTION
        DOWNLOAD_DRIVE=$(echo "$USB_DRIVES" | sed -n "${DOWNLOAD_SELECTION}p" | awk '{print $1}')
        DOWNLOAD_FS=$(echo "$USB_DRIVES" | sed -n "${DOWNLOAD_SELECTION}p" | awk '{print $3}')
    fi

    # Define mount points
    STORAGE_MOUNT="/mnt/storage"
    DOWNLOAD_MOUNT="/mnt/downloads"

    # Mount storage drive
    echo "Mounting $STORAGE_DRIVE to $STORAGE_MOUNT..."
    sudo mkdir -p "$STORAGE_MOUNT"
    if [[ "$STORAGE_FS" == "ntfs" ]]; then
        sudo mount -t ntfs-3g "$STORAGE_DRIVE" "$STORAGE_MOUNT"
    else
        sudo mount "$STORAGE_DRIVE" "$STORAGE_MOUNT"
    fi
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to mount $STORAGE_DRIVE. Please check the drive and try again."
        exit 1
    fi

    # Update fstab for storage drive
    update_fstab "$STORAGE_MOUNT" "$STORAGE_DRIVE"

    # Mount download drive if different
    if [[ "$SAME_DRIVE" =~ ^[Nn]$ ]]; then
        echo "Mounting $DOWNLOAD_DRIVE to $DOWNLOAD_MOUNT..."
        sudo mkdir -p "$DOWNLOAD_MOUNT"
        if [[ "$DOWNLOAD_FS" == "ntfs" ]]; then
            sudo mount -t ntfs-3g "$DOWNLOAD_DRIVE" "$DOWNLOAD_MOUNT"
        else
            sudo mount "$DOWNLOAD_DRIVE" "$DOWNLOAD_MOUNT"
        fi
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to mount $DOWNLOAD_DRIVE. Please check the drive and try again."
            exit 1
        fi

        # Update fstab for download drive
        update_fstab "$DOWNLOAD_MOUNT" "$DOWNLOAD_DRIVE"
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
    else
        echo "NFS export for $STORAGE_MOUNT already exists. Skipping."
    fi

    # Add download directory if not already in exports
    if ! grep -q "$DOWNLOAD_MOUNT" "$EXPORTS_FILE"; then
        echo "$DOWNLOAD_MOUNT *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a "$EXPORTS_FILE"
    else
        echo "NFS export for $DOWNLOAD_MOUNT already exists. Skipping."
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

    # Mark success
    sed -i 's/SHARE_SETUP_SUCCESS=0/SHARE_SETUP_SUCCESS=1/' "$ENV_FILE"
}


# Create Docker Compose file
create_docker_compose() {
    if [[ "$docker_compose_success" == "1" ]]; then
        echo "Docker Compose stack is already deployed. Skipping."
        return
    fi    
    
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
      - $DOCKER_DIR/gluetun:/gluetun
    env_file:
      - $DOCKER_DIR/gluetun/.env
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
    echo "Docker Compose stack deployed successfully."
    sed -i 's/docker_compose_success=0/docker_compose_success=1/' "$ENV_FILE"
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
    # Source the .env file after creating it
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi
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
