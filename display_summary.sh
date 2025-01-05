#!/bin/bash

# Source utilities
source ./utils.sh

# Load environment variables
load_env

display_summary() {
    # Display completion messages
    whiptail --title "Setup Complete" --msgbox "All steps completed successfully." 10 60
    whiptail --title "Setup Complete" --msgbox "Setup complete. Update the .env file with credentials if not already done." 10 60
    whiptail --title "Setup Complete" --msgbox "Setup Summary:" 10 60
    whiptail --title "Setup Complete" --msgbox "Docker services are running:" 10 60

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

    # Display file shares
    echo "File shares available:"
    if [[ "$SHARE_METHOD" == "1" ]]; then
        echo "  Samba Shares:"
        printf '    \\\\%s\\\\Movies\n' "$SERVER_IP"
        printf '    \\\\%s\\\\TVShows\n' "$SERVER_IP"
        printf '    \\\\%s\\\\Downloads\n' "$SERVER_IP"
    elif [[ "$SHARE_METHOD" == "2" ]]; then
        echo "  NFS Shares:"
        echo "    $SERVER_IP:/mnt/storage/Movies"
        echo "    $SERVER_IP:/mnt/storage/TVShows"
    fi

    # Save services and URLs to a file
    for SERVICE in "${!SERVICES_AND_PORTS[@]}"; do
        echo "$SERVICE: ${SERVICES_AND_PORTS[$SERVICE]}" >> "$HOME/services_urls.txt"
    done
    echo "URLs saved to $HOME/services_urls.txt"
}
