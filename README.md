🐳 Raspberry Pi Docker Stack with VPN, Tailscale, and Media Management

This project automates the setup of a Docker-based media server stack on a Raspberry Pi. It includes VPN integration, Tailscale for secure remote access, and popular media management tools. The stack is highly customizable and uses Docker Compose for easy deployment.
Features

    VPN Integration: External traffic is routed through a VPN container for privacy (using gluetun).
    Tailscale: Enables secure remote access to the Raspberry Pi and containers via Tailscale IP.
    Media Management Tools:
        🗂️ Jackett: Indexer proxy for torrent and Usenet sites.
        🎥 Radarr: Movies download manager.
        📺 Sonarr: TV shows download manager.
        🌐 Transmission: Torrent downloader.
        📦 NZBGet: Usenet downloader.
    Watchtower: Automatic updates for Docker containers, running outside the VPN for unrestricted access.
    Customizable: Container names and image providers can be easily swapped.

Requirements

    Raspberry Pi running a Linux-based OS, I am using RP5 8GB.
    Docker and Docker Compose installed.
    Private Internet Access as VPN Provider.
    #AirVPN, FastestVPN, Ivpn, Mullvad, NordVPN, Perfect privacy, ProtonVPN, Surfshark and Windscribe will follow.
    Tailscale account for secure remote access.


Create tailscale auth key
![image](https://github.com/user-attachments/assets/e4d496f7-0368-4870-88b7-c6222378be4e)



Installation

    Clone this repository:

git clone https://github.com/<your-username>/<repo-name>.git
cd <repo-name>

Make the setup script executable:

chmod +x setup.sh

Run the setup script:

./setup.sh

This script will:

    Install dependencies (Docker, Docker Compose, Tailscale).
    Configure Tailscale.
    Set up a VPN container network.
    Deploy the media stack using Docker Compose.

Update the .env file with your credentials:

nano ~/docker/.env

Example .env file:

PIA_USERNAME=your_pia_username
PIA_PASSWORD=your_pia_password
TAILSCALE_AUTH_KEY=your_tailscale_auth_key

Start the stack:

    docker-compose --env-file ~/docker/.env -f ~/docker/docker-compose.yml up -d

Accessing the Services
Service	Default Port	URL
Jackett	9117	http://<Pi IP>:9117
Sonarr	8989	http://<Pi IP>:8989
Radarr	7878	http://<Pi IP>:7878
Transmission	9091	http://<Pi IP>:9091
NZBGet	6789	http://<Pi IP>:6789

You can also access these services via your Tailscale IP:

http://<Tailscale IP>:<Port>

How It Works

    VPN Routing:
        Containers (e.g., jackett, radarr, sonarr, etc.) are routed through the VPN container (gluetun) for privacy.
        The VPN container ensures external traffic (e.g., torrents, APIs) uses the VPN’s secure connection.
        Fail-safe: If the VPN drops, traffic from dependent containers is blocked.

    Tailscale:
        Provides remote access to the Raspberry Pi and all exposed container ports.
        Bypasses the VPN, enabling efficient and direct access over Tailscale’s secure mesh network.

    Watchtower:
        Runs outside the VPN (network_mode: bridge) to ensure it has unrestricted access to Docker registries.
        Automatically updates containers in the stack when new images are available.

Customizing the Stack

You can customize the container names and images in the setup.sh script. For example:

# Jackett
JACKETT_CONTAINER="jackett"
JACKETT_IMAGE="linuxserver/jackett"

To use a different image, update the *_IMAGE variables and re-run the setup.
Testing

    Local Access:
        Open a browser and navigate to http://<Pi IP>:<Port>.

    Tailscale Access:
        Use your Tailscale IP instead of the Raspberry Pi's local IP.

    VPN Routing:
        Verify containers are routing traffic through the VPN:

    docker exec -it transmission curl ifconfig.me

    The output should show the VPN's external IP.

Watchtower Logs:

    Check Watchtower for updates:

        docker logs watchtower

Troubleshooting
VPN Connection Issues

    Ensure your VPN credentials are correct in the .env file.
    Check the logs of the vpn container:

    docker logs vpn

Tailscale Authentication

    If Tailscale fails to start, authenticate manually:

    sudo tailscale up

Container Access

    If you can’t access a container, ensure the stack is running:

    docker ps

License

This project is licensed under the MIT License.
Contributing

Feel free to submit issues or pull requests to improve this stack. Contributions are welcome!
Acknowledgments

    Docker
    LinuxServer.io
    Gluetun
    Tailscale
    Watchtower
