#!/bin/bash
# General Variables
DOCKER_DIR="$HOME/docker"

# Check and source the .env file
ENV_FILE="$DOCKER_DIR/.env"
# Source utilities
source ./utils.sh

# Load environment variables
load_env

#GET_IPLAYER CONFIG CREATION
create_config_json() {
    if [[ "$GET_IPLAYER_CREATE_CONFIG_SUCCESS" == "1" ]]; then
        whiptail --title "Get Iplayer" --msgbox "IPlayer Get config already setup. Skipping." 10 60
        return
    fi   
    whiptail --title "Get Iplayer" --msgbox  "Creating config.json for SonarrAutoImport..." 10 60

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

    whiptail --title "Get Iplayer" --msgbox   "config.json created at $CONFIG_FILE." 10 60
    whiptail --title "Get Iplayer" --msgbox   "Please update the API keys in the config file before running the container." 10 60
    sed -i 's/CREATE_CONFIG_SUCCESS=0/GET_IPLAYER_CREATE_CONFIG_SUCCESS==1/' "$ENV_FILE"
}

# Setup Tailscale
setup_tailscale() {
    if [[ "$TAILSCALE_INSTALL_SUCCESS" == "1" ]]; then
        whiptail --title "Tailscale" --msgbox "PIA already setup. Skipping."
        return
    fi

    if whiptail --title "Tailscale" --yesno "Do you want to set up Tailscale?" 10 60; then
        show_progress "curl -fsSL https://tailscale.com/install.sh | sh" "Installing Tailscale..."

        local auth_key
        auth_key=$(whiptail --inputbox "Enter Tailscale Auth Key (leave blank for manual setup):" 10 60 3>&1 1>&2 2>&3)

        if [ -z "$auth_key" ]; then
            sudo tailscale up --accept-routes=false
        else
            sudo tailscale up --accept-routes=false --authkey="$auth_key"
        fi

        whiptail --title "Tailscale" --msgbox "Tailscale setup completed." 10 60
        sed -i 's/TAILSCALE_INSTALL_SUCCESS=0/TAILSCALE_INSTALL_SUCCESS=1/' "$ENV_FILE"
    fi
}

# Prompt user for missing VPN credentials
prompt_for_vpn_credentials() {
    if [[ "$PIA_USERNAME" == "your_vpn_username" || -z "$PIA_USERNAME" ]]; then
        PIA_USERNAME=$(whiptail --inputbox "Enter your VPN username:" 10 60 "" 3>&1 1>&2 2>&3)
        sed -i "s/^PIA_USERNAME=.*/PIA_USERNAME=$PIA_USERNAME/" "$ENV_FILE"
    fi

    if [[ "$PIA_PASSWORD" == "your_vpn_password" || -z "$PIA_PASSWORD" ]]; then
        PIA_PASSWORD=$(whiptail --passwordbox "Enter your VPN password:" 10 60 "" 3>&1 1>&2 2>&3)
        sed -i "s/^PIA_PASSWORD=.*/PIA_PASSWORD=$PIA_PASSWORD/" "$ENV_FILE"
    fi
}

setup_pia_vpn() {
    if [[ "$PIA_SETUP_SUCCESS" == "1" ]]; then
        whiptail --title "PIA" --msgbox  "PIA already setup. Skipping."
        return
    fi
    
    whiptail --title "Setup PIA VPN" --msgbox "Setting PIA config file for $VPN_CONTAINER..." 10 60

    # Source the .env file to load PIA credentials
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    else
        whiptail --title "Setup PIA VPN" --msgbox "Grabbing PIA Creds from $ENV_FILE..." 10 60
        exit 1
    fi

    # Ensure PIA credentials are set
    if [[ -z "$PIA_USERNAME" || -z "$PIA_PASSWORD" ]]; then
        whiptail --title "Setup PIA VPN" --msgbox "Error: PIA credentials are not set. Ensure PIA_USERNAME and PIA_PASSWORD are correctly provided in the .env file." 10 60
        exit 1
    fi

    # Create the gluetun directory for configuration
    GLUETUN_DIR="$DOCKER_DIR/$VPN_CONTAINER"
    whiptail --title "Create $VPN_CONTAINER config" --msgbox  "Creating $VPN_CONTAINER  configuration directory at $GLUETUN_DIR..." 10 60
    mkdir -p "$GLUETUN_DIR"

    # Write the environment variables to a Docker Compose file
    cat > "$GLUETUN_DIR/.env" <<EOF
VPN_SERVICE_PROVIDER=private internet access
OPENVPN_USER=$PIA_USERNAME
OPENVPN_PASSWORD=$PIA_PASSWORD
SERVER_REGIONS=Netherlands
EOF

    whiptail --title "Create $VPN_CONTAINER config" --msgbox  "OpenVPN setup complete. Configuration saved to $GLUETUN_DIR/.env." 10 60
    # Mark success
    sed -i 's/PIA_SETUP_SUCCESS=0/PIA_SETUP_SUCCESS=1/' "$ENV_FILE"
}

