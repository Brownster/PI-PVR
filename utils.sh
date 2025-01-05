#!/bin/bash

DOCKER_DIR="$HOME/docker"

# Check and source the .env file
ENV_FILE="$DOCKER_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# utils.sh
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    else
        echo "Error: .env file not found at $ENV_FILE"
        exit 1
    fi
}


#Detect Linux Distro
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        whiptail --title "Error" --msgbox "Unsupported Linux distribution." 10 60
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
            whiptail --title "Error" --msgbox "Unsupported Linux distribution: $DISTRO" 10 60
            exit 1
            ;;
    esac
}

# Write Distro to .env file
write_distro_to_env() {
    if grep -q "^DISTRO=" "$ENV_FILE"; then
        sed -i "s/^DISTRO=.*/DISTRO=$DISTRO/" "$ENV_FILE"
    else
        echo "DISTRO=$DISTRO" >> "$ENV_FILE"
    fi
}

# Function to update /etc/fstab with the new mount point
update_fstab() {
    local mount_point="$1"
    local device="$2"

    # Get the UUID of the device
    local uuid=$(blkid -s UUID -o value "$device")
    if [[ -z "$uuid" ]]; then
        whiptail --title "error" --msgbox   "Error: Could not retrieve UUID for device $device."
        exit 1
    fi

    # Check if the mount point is already in /etc/fstab
    if grep -q "$mount_point" /etc/fstab; then
        whiptail --title "Fstab" --msgbox "Mount point $mount_point already exists in /etc/fstab. Skipping." 10 60
    else
        whiptail --title "Fstab" --msgbox "Adding $mount_point to /etc/fstab..."
        echo "UUID=$uuid $mount_point auto defaults 0 2" | sudo tee -a /etc/fstab > /dev/null
    fi
}


# Generate a Tailwind-styled HTML output for services and shares
generate_tailwind_html() {
    local html_file="$DOCKER_DIR/services_and_shares.html"

    # Start the HTML document
    cat > "$html_file" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Services and Shares</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100 text-gray-900 font-sans">
    <div class="container mx-auto p-4">
        <h1 class="text-2xl font-bold mb-4">Services and their URLs</h1>
        <ul class="list-disc list-inside">
EOF

    # Add the services and URLs
    for SERVICE in "${!SERVICES_AND_PORTS[@]}"; do
        echo "            <li><span class='font-semibold'>$SERVICE</span>: <a href='${SERVICES_AND_PORTS[$SERVICE]}' target='_blank' class='text-blue-500 underline'>${SERVICES_AND_PORTS[$SERVICE]}</a></li>" >> "$html_file"
    done

    # Add the shares based on the selected method
    case "$SHARE_METHOD" in
        1)
            echo "        </ul>" >> "$html_file"
            echo "        <h2 class='text-xl font-bold mt-6'>Samba Shares</h2>" >> "$html_file"
            echo "        <ul class='list-disc list-inside'>" >> "$html_file"
            printf "            <li>\\\\%s\\\\Movies</li>\n" "$SERVER_IP" >> "$html_file"
            printf "            <li>\\\\%s\\\\TVShows</li>\n" "$SERVER_IP" >> "$html_file"
            ;;
        2)
            echo "        </ul>" >> "$html_file"
            echo "        <h2 class='text-xl font-bold mt-6'>NFS Shares</h2>" >> "$html_file"
            echo "        <ul class='list-disc list-inside'>" >> "$html_file"
            echo "            <li>$SERVER_IP:/mnt/storage/Movies</li>" >> "$html_file"
            echo "            <li>$SERVER_IP:/mnt/storage/TVShows</li>" >> "$html_file"
            ;;
    esac

    # Close the HTML tags
    cat >> "$html_file" <<EOF
        </ul>
    </div>
</body>
</html>
EOF

    # Inform the user
    echo "HTML output generated: $html_file"
}
