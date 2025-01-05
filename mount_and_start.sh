#!/bin/bash
# variables
DOCKER_DIR="$HOME/docker"

# Check and source the .env file
ENV_FILE="$DOCKER_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    whiptail --title "Setup Mount persistance and start docker" --msgbox "Error: .env file not found at $ENV_FILE"
    exit 1
fi


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
