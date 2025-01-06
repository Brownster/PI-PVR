#!/bin/bash
# Server Variables
SHARE_METHOD=""
SERVER_IP=$(hostname -I | awk '{print $1}')
# General Variables
CONTAINER_NETWORK="vpn_network"
DOCKER_DIR="$HOME/docker"
ENV_FILE="$DOCKER_DIR/.env"
ENV_URL="https://raw.githubusercontent.com/Brownster/docker-compose-pi/refs/heads/main/.env"
COMPOSE_URL="https://raw.githubusercontent.com/Brownster/docker-compose-pi/refs/heads/main/docker-compose.yml"

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

source ./docker_setup.sh
source ./storage_setup.sh
source ./vpn_setup.sh
source ./install_dependencies.sh
source ./utils.sh
source ./create_env.sh
source ./create_configs.sh
source ./deploy_docker.sh
source ./mount_and_start.sh
source ./update_compose.sh
source ./display_summary.sh
source ./fstab.sh


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
    whiptail --title "Setup Script" --msgbox "Welcome to the setup script!" 10 60
    create_env_file
    # Source the .env file after creating it
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi
    detect_distro
    write_distro_to_env
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
    display_summary
    generate_tailwind_html
}

main
