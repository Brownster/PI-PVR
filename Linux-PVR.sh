#!/bin/bash
# Server Variables
SHARE_METHOD=""
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

#Detect Linux Distro
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        echo "Unsupported Linux distribution."
        exit 1
    fi
}

#Alter install based on $DISTRO
install_package() {
    case $DISTRO in
        ubuntu|debian)
            sudo apt-get install -y "$@"
            ;;
        fedora|centos|rhel)
            sudo dnf install -y "$@"
            ;;
        arch)
            sudo pacman -S --noconfirm "$@"
            ;;
        *)
            echo "Unsupported Linux distribution: $DISTRO"
            exit 1
            ;;
    esac
}


# Create .env file for sensitive data
create_env_file() {
    echo "Creating .env file for sensitive data..."
    mkdir -p "$DOCKER_DIR"

    # Define the location of the .env file
    ENV_FILE="$DOCKER_DIR/.env"

    # URL of the .env file in the repository
    ENV_URL="https://raw.githubusercontent.com/Brownster/docker-compose-pi/refs/heads/main/.env"

    if [[ ! -f "$ENV_FILE" ]]; then
        # Download the .env file
        if curl -fSL "$ENV_URL" -o "$ENV_FILE"; then
            echo ".env file downloaded successfully to $ENV_FILE."
            chmod 600 "$ENV_FILE"
        else
            echo "Failed to download .env file from $ENV_URL."
            return 1
        fi
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
        "search" : "Escape_to_the_Country_Series_(\\d+)_-_S(\\d+)E(\\d+)_-_.+\\.mp4",
        "replace" : "Escape to the Country S\$2E\$3.mp4"
      },
      {
        "search" : "Escape_to_the_Country_Series_(\\d+)_Extended_Versions_-_S(\\d+)E(\\d+)_-_.+\\.mp4",
        "replace" : "Escape to the Country Extended S\$2E\$3.mp4"
      },
      {
        "search" : "Escape_to_the_Country_Series_(\\d+)_-_Episode_(\\d+)\\.mp4",
        "replace" : "Escape to the Country S\$1E\$2.mp4"
      },
      {
        "search" : "Escape_to_the_Country_(\\d{4})_Season_(\\d+)_-_Episode_(\\d+)\\.mp4",
        "replace" : "Escape to the Country S\$2E\$3.mp4"
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
    GLUETUN_DIR="$DOCKER_DIR/$VPN_CONTAINER"
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


# Ensure DOCKER_DIR exists
ensure_docker_dir() {
    if [[ ! -d "$DOCKER_DIR" ]]; then
        echo "Creating Docker directory at $DOCKER_DIR..."
        mkdir -p "$DOCKER_DIR"
    fi

    if [[ ! -f "$ENV_FILE" ]]; then
        echo "Creating .env file at $ENV_FILE..."
        touch "$ENV_FILE"
        chmod 600 "$ENV_FILE"
    fi
}

# Initial Setup Check
initial_setup_check() {
    echo "Checking if storage is already configured..."
    if [[ -d "/mnt/storage" ]]; then
        read -r -p "Storage appears to be configured. Do you want to skip to share creation? (y/n): " RESPONSE
        if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
            create_shares
            exit 0
        fi
    fi
}

# Storage Selection
select_storage() {
    echo "Choose your storage type:"
    echo "1. Local Storage"
    echo "2. USB Storage"
    echo "3. Network Storage"
    read -r -p "Enter your choice (1/2/3): " STORAGE_TYPE

    case "$STORAGE_TYPE" in
        1)
            read -r -p "Enter the path for local storage: " LOCAL_STORAGE_PATH
            STORAGE_MOUNT="$LOCAL_STORAGE_PATH"
            ;;
        2)
            setup_usb_storage
            ;;
        3)
            setup_network_storage
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

# Mount USB Storage
setup_usb_storage() {
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

    STORAGE_MOUNT="/mnt/storage"
    echo "Mounting $STORAGE_DRIVE to $STORAGE_MOUNT..."
    sudo mkdir -p "$STORAGE_MOUNT"
    if [[ "$STORAGE_FS" == "ntfs" ]]; then
        sudo mount -t ntfs-3g "$STORAGE_DRIVE" "$STORAGE_MOUNT"
    else
        sudo mount "$STORAGE_DRIVE" "$STORAGE_MOUNT"
    fi

    update_fstab "$STORAGE_MOUNT" "$STORAGE_DRIVE"
}

# Mount Network Storage
setup_network_storage() {
    read -r -p "Enter the network share path (e.g., //server/share): " NETWORK_PATH
    read -r -p "Enter the mount point (e.g., /mnt/network): " NETWORK_MOUNT

    echo "Mounting network share..."
    sudo mkdir -p "$NETWORK_MOUNT"
    sudo mount -t cifs "$NETWORK_PATH" "$NETWORK_MOUNT" -o username=guest

    update_fstab "$NETWORK_MOUNT" "$NETWORK_PATH"
}

# Update fstab
update_fstab() {
    local mount_point="$1"
    local device="$2"

    echo "Adding $mount_point to /etc/fstab..."
    if grep -q "$mount_point" /etc/fstab; then
        echo "$mount_point is already in /etc/fstab. Skipping."
    else
        echo "$device $mount_point auto defaults 0 2" | sudo tee -a /etc/fstab > /dev/null
    fi
}

# Folder Assignment
assign_folders() {
    MOVIES_DIR="$STORAGE_MOUNT/Movies"
    TVSHOWS_DIR="$STORAGE_MOUNT/TVShows"
    DOWNLOADS_DIR="$STORAGE_MOUNT/Downloads"

    for DIR in "$MOVIES_DIR" "$TVSHOWS_DIR" "$DOWNLOADS_DIR"; do
        if [[ ! -d "$DIR" ]]; then
            echo "Creating directory $DIR..."
            sudo mkdir -p "$DIR"
            sudo chmod 775 "$DIR"
            sudo chown "$USER:$USER" "$DIR"
        fi
    done
}

# Create Shares
create_shares() {
    echo "Choose sharing method:"
    echo "1. Samba"
    echo "2. NFS"
    read -r -p "Enter your choice (1/2): " SHARE_METHOD

    case "$SHARE_METHOD" in
        1)
            setup_samba_shares
            ;;
        2)
            setup_nfs_shares
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

# Setup Samba Shares
setup_samba_shares() {
    echo "Configuring Samba..."
    if ! command -v smbd &> /dev/null; then
        echo "Samba is not installed. Installing now..."
        sudo install_package install -y samba samba-common-bin
    else
        echo "Samba is already installed. Skipping installation."
    fi

    SAMBA_CONFIG="/etc/samba/smb.conf"
    if ! grep -q "\[Movies\]" "$SAMBA_CONFIG"; then
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
   path = $DOWNLOADS_DIR
   browseable = yes
   read only = no
   guest ok = yes
EOF
        sudo systemctl restart smbd
    fi
    echo "Samba shares configured."
}

# Setup NFS Shares
setup_nfs_shares() {
    echo "Configuring NFS..."
    sudo install_package install -y nfs-kernel-server
    EXPORTS_FILE="/etc/exports"

    for DIR in "$MOVIES_DIR" "$TVSHOWS_DIR" "$DOWNLOADS_DIR"; do
        if ! grep -q "$DIR" "$EXPORTS_FILE"; then
            echo "$DIR *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a "$EXPORTS_FILE"
        fi
    done

    sudo exportfs -ra
    sudo systemctl restart nfs-kernel-server
    echo "NFS shares configured."
}

# Update .env File
update_env_file() {
    echo "Updating .env file with folder locations..."
    cat >> "$ENV_FILE" <<EOF
MOVIES_FOLDER="$MOVIES_DIR"
TVSHOWS_FOLDER="$TVSHOWS_DIR"
DOWNLOADS_FOLDER="$DOWNLOADS_DIR"
EOF
    echo ".env file updated."
}

# Final Review
final_review() {
    echo "Setup complete. Summary:"
    echo "Storage mounted at: $STORAGE_MOUNT"
    echo "Movies folder: $MOVIES_DIR"
    echo "TV Shows folder: $TVSHOWS_DIR"
    echo "Downloads folder: $DOWNLOADS_DIR"
    if [[ "$SHARE_METHOD" == "1" ]]; then
        echo "Samba shares available at:"
        printf '\\%s\Movies\
' "$SERVER_IP"
        printf '\\%s\TVShows\
' "$SERVER_IP"
        printf '\\%s\Downloads\
' "$SERVER_IP"
    elif [[ "$SHARE_METHOD" == "2" ]]; then
        echo "NFS shares available at:"
        echo "$SERVER_IP:$MOVIES_DIR"
        echo "$SERVER_IP:$TVSHOWS_DIR"
        echo "$SERVER_IP:$DOWNLOADS_DIR"

    # Mark success
    sed -i 's/SHARE_SETUP_SUCCESS=0/SHARE_SETUP_SUCCESS=1/' "$ENV_FILE"
    fi
}


# Create Docker Compose file
create_docker_compose() {
    if [[ "$docker_compose_success" == "1" ]]; then
        echo "Docker Compose stack is already deployed. Skipping."
        return
    fi    

    echo "Creating Docker Compose file from repository..."
    
    # URL of the Docker Compose file in the repository
    COMPOSE_URL="https://raw.githubusercontent.com/Brownster/docker-compose-pi/refs/heads/main/docker-compose.yml"
    ENV_URL="https://raw.githubusercontent.com/Brownster/docker-compose-pi/refs/heads/main/.env"
    
    # Directory to save the Docker Compose file
    mkdir -p "$DOCKER_DIR"

    # Download the Docker Compose file
    if curl -fSL "$COMPOSE_URL" -o "$DOCKER_DIR/docker-compose.yml"; then
        echo "Docker Compose file downloaded successfully to $DOCKER_DIR/docker-compose.yml"

    fi    
    sed -i 's/docker_compose_success=0/docker_compose_success=1/' "$ENV_FILE"
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
        sudo install_package remove -y "$pkg"
    done

    echo "Adding Docker's official GPG key and repository for Docker..."
    sudo install_package update
    sudo install_package install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo install_package update

    echo "Installing Docker Engine, Docker Compose, and related packages..."
    sudo install_package install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Installing other required dependencies: curl, jq, git..."
    sudo install_package install -y curl jq git

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

    # Temporarily disable get_iplayer in docker-compose.yml
    local compose_file="$DOCKER_DIR/docker-compose.yml"
    echo "Disabling get_iplayer container for the first run..."
    sed -i '/get_iplayer:/,/restart: unless-stopped/ s/^/#/' "$compose_file"

    # Attempt to deploy the Docker Compose stack
    if ! docker compose --env-file "$ENV_FILE" -f "$compose_file" up -d; then
        echo "Error: Failed to deploy Docker Compose stack."
        echo "This is likely due to recent changes to Docker permissions."
        echo "Please log out and log back in to refresh your user session, then restart this script."
        exit 1
    fi

    echo "Docker Compose stack deployed successfully."
    echo "Please retrieve the API keys for Radarr and Sonarr and update the .env file."

    # Notify user to uncomment get_iplayer and restart the stack
    echo "To enable get_iplayer, redeploy the stack after adding api keys:"
    echo "  sed -i '/#get_iplayer:/,/restart: unless-stopped/ s/^#//' \"$compose_file\""
}



setup_mount_and_docker_start() {
    echo "Configuring drives to mount at boot and Docker to start afterwards..."

    # Variables for mount points and device paths
    STORAGE_MOUNT="/mnt/storage"
    #DOWNLOAD_MOUNT="/mnt/downloads"

    # Get device UUIDs for fstab
    STORAGE_UUID=$(blkid -s UUID -o value "$(findmnt -nT "$STORAGE_MOUNT" | awk '{print $2}')")
    #DOWNLOAD_UUID=$(blkid -s UUID -o value "$(findmnt -nT "$DOWNLOAD_MOUNT" | awk '{print $2}')")

    if [[ -z "$STORAGE_UUID" ]]; then
        echo "Error: Could not determine UUID for the storage mount point: $STORAGE_MOUNT."
        exit 1
    fi

    # Update /etc/fstab for persistent mount
    echo "Updating /etc/fstab..."
    sudo bash -c "cat >> /etc/fstab" <<EOF
UUID=$STORAGE_UUID $STORAGE_MOUNT ext4 defaults 0 2
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
DOCKER_COMPOSE_FILE="$HOME/docker/docker-compose.yml"

# Wait until mounts are ready
until mountpoint -q "$STORAGE_MOUNT"; do
    echo "Waiting for drive to be mounted..."
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
    detect_distro
    setup_tailscale
    install_dependencies
    setup_pia_vpn
    create_docker_compose
    create_config_json
    ensure_docker_dir
    initial_setup_check
    select_storage
    assign_folders
    create_shares
    update_env_file
    final_review
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

    for SERVICE in "${!SERVICES_AND_PORTS[@]}"; do
        echo "$SERVICE: ${SERVICES_AND_PORTS[$SERVICE]}" >> "$HOME/services_urls.txt"
    done
    echo "URLs saved to $HOME/services_urls.txt"



    fi

}

main
