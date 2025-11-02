#!/bin/bash
# Main setup script

# Exit on error
set -euo pipefail

# Run the PVR setup script
./setup-pvr.sh

# Run the Spotify installer
./install_spotify.sh
