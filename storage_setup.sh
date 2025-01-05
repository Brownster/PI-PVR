#!/bin/bash

DOCKER_DIR="$HOME/docker"
ENV_FILE="$DOCKER_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    whiptail --title "Initial Storage Setup Check" --msgbox "Error: .env file not found at $ENV_FILE" 10 60
    exit 1
fi

# Initial Setup Check
initial_setup_check() {
    whiptail --title "Initial Storage Setup Check" --msgbox  "Checking if storage is already configured..."
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
    STORAGE_TYPE=$(whiptail --title "Storage Selection" --menu "Choose your storage type:" 15 60 4 \
        "1" "Local Storage" \
        "2" "USB Storage" \
        "3" "Network Storage" 3>&1 1>&2 2>&3)

    case "$STORAGE_TYPE" in
        1)
            LOCAL_STORAGE_PATH=$(whiptail --inputbox "Enter the path for local storage:" 10 60 3>&1 1>&2 2>&3)
            STORAGE_MOUNT="$LOCAL_STORAGE_PATH"
            ;;
        2)
            setup_usb_storage
            ;;
        3)
            setup_network_storage
            ;;
        *)
            whiptail --title "Error" --msgbox "Invalid choice. Exiting." 10 60
            exit 1
            ;;
    esac
}

# Mount USB Storage
setup_usb_storage() {
    USB_DRIVES=$(lsblk -o NAME,SIZE,TYPE,FSTYPE | awk '/part/ {print "/dev/"$1, $2, $4}')

    if [[ -z "$USB_DRIVES" ]]; then
        whiptail --title "Error" --msgbox "No USB drives detected. Please ensure they are connected and retry." 10 60
        exit 1
    fi

    DRIVE_SELECTION=$(echo "$USB_DRIVES" | nl | whiptail --title "USB Storage" --menu "Select a drive:" 15 60 8 3>&1 1>&2 2>&3)
    STORAGE_DRIVE=$(echo "$USB_DRIVES" | sed -n "${DRIVE_SELECTION}p" | awk '{print $1}')
    STORAGE_FS=$(echo "$USB_DRIVES" | sed -n "${DRIVE_SELECTION}p" | awk '{print $3}')

    STORAGE_MOUNT="/mnt/storage"
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
    NETWORK_PATH=$(whiptail --inputbox "Enter the network share path (e.g., //server/share):" 10 60 3>&1 1>&2 2>&3)
    NETWORK_MOUNT=$(whiptail --inputbox "Enter the mount point (e.g., /mnt/network):" 10 60 3>&1 1>&2 2>&3)

    sudo mkdir -p "$NETWORK_MOUNT"
    sudo mount -t cifs "$NETWORK_PATH" "$NETWORK_MOUNT" -o username=guest

    update_fstab "$NETWORK_MOUNT" "$NETWORK_PATH"
}

# Update fstab
update_fstab() {
    local mount_point="$1"
    local device="$2"

    if grep -q "$mount_point" /etc/fstab; then
        whiptail --title "Info" --msgbox "Mount point $mount_point already exists in /etc/fstab. Skipping." 10 60
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
            sudo mkdir -p "$DIR"
            sudo chmod 775 "$DIR"
            sudo chown "$USER:$USER" "$DIR"
        fi
    done
}

# Create Shares
create_shares() {
    SHARE_METHOD=$(whiptail --title "Share Setup" --menu "Choose sharing method:" 15 60 4 \
        "1" "Samba" \
        "2" "NFS" 3>&1 1>&2 2>&3)

    case "$SHARE_METHOD" in
        1)
            setup_samba_shares
            ;;
        2)
            setup_nfs_shares
            ;;
        *)
            whiptail --title "Error" --msgbox "Invalid choice. Exiting." 10 60
            exit 1
            ;;
    esac
}

# Setup Samba Shares
setup_samba_shares() {
    if ! command -v smbd &> /dev/null; then
        sudo install_package samba samba-common-bin
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

    whiptail --title "Samba Shares" --msgbox "Samba shares configured." 10 60
}

# Setup NFS Shares
setup_nfs_shares() {
    sudo install_package nfs-kernel-server

    EXPORTS_FILE="/etc/exports"
    for DIR in "$MOVIES_DIR" "$TVSHOWS_DIR" "$DOWNLOADS_DIR"; do
        if ! grep -q "$DIR" "$EXPORTS_FILE"; then
            echo "$DIR *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a "$EXPORTS_FILE"
        fi
    done

    sudo exportfs -ra
    sudo systemctl restart nfs-kernel-server

    whiptail --title "NFS Shares" --msgbox "NFS shares configured." 10 60
}

# Update .env File
update_env_file() {
    whiptail --title "ENV File" --msgbox "Updating .env file with folder locations..."
    cat >> "$ENV_FILE" <<EOF
MOVIES_FOLDER="$MOVIES_DIR"
TVSHOWS_FOLDER="$TVSHOWS_DIR"
DOWNLOADS_FOLDER="$DOWNLOADS_DIR"
EOF
    echo ".env file updated."
}

# Final Review
# Final Review
final_review() {
    local summary="Setup complete. Summary:\n\n"
    summary+="Storage mounted at: $STORAGE_MOUNT\n"
    summary+="Movies folder: $MOVIES_DIR\n"
    summary+="TV Shows folder: $TVSHOWS_DIR\n"
    summary+="Downloads folder: $DOWNLOADS_DIR\n\n"

    if [[ "$SHARE_METHOD" == "1" ]]; then
        summary+="Samba shares available at:\n"
        summary+="\\\\${SERVER_IP}\\Movies\n"
        summary+="\\\\${SERVER_IP}\\TVShows\n"
        summary+="\\\\${SERVER_IP}\\Downloads\n"
    elif [[ "$SHARE_METHOD" == "2" ]]; then
        summary+="NFS shares available at:\n"
        summary+="${SERVER_IP}:${MOVIES_DIR}\n"
        summary+="${SERVER_IP}:${TVSHOWS_DIR}\n"
        summary+="${SERVER_IP}:${DOWNLOADS_DIR}\n"
    fi

    whiptail --title "Setup Complete" --msgbox "$summary" 20 70

    # Mark success
    sed -i 's/SHARE_SETUP_SUCCESS=0/SHARE_SETUP_SUCCESS=1/' "$ENV_FILE"
    fi
}
