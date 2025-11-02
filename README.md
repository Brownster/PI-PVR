# Raspberry Pi Docker Stack with VPN, Tailscale, and Media Management

This project automates the setup of a Docker-based media server stack on a Raspberry Pi or any Linux-based system. It includes VPN integration, Tailscale for secure remote access, and popular media management tools. The stack is highly customizable and uses Docker Compose for easy deployment.

## Requirements

*   Raspberry Pi or Linux-based system.
*   Docker and Docker Compose installed (handled by the script if not already installed).
*   Private Internet Access as the VPN provider.
*   Tailscale account for secure remote access.
*   Pre-configured mount points at `/mnt/storage`, `/mnt/downloads`, and `/mnt/backup`.

## Installation

1.  Clone this repository:

    ```bash
    git clone https://github.com/Brownster/PI-PVR.git
    cd PI-PVR
    ```

2.  Make the setup script executable:

    ```bash
    chmod +x setup.sh
    ```

3.  Run the setup script:

    ```bash
    ./setup.sh
    ```

    Follow the on-screen prompts to configure the environment and VPN.

## Usage

### Debug Mode

Run with `--debug` to see detailed command outputs:

```bash
./setup.sh --debug
```

### Update Docker Compose Stack

This feature is not available in the simplified script.

## Configuration

### Environment Variables

The script creates an `.env` file for managing sensitive data. Update this file as needed:

```bash
nano ~/docker/.env
```

Example `.env` file:

```
PIA_USERNAME=your_pia_username
PIA_PASSWORD=your_pia_password
TAILSCALE_AUTH_KEY=your_tailscale_auth_key
TIMEZONE=Europe/London
MOVIES_FOLDER="Movies"
TVSHOWS_FOLDER="TVShows"
DOWNLOADS="/mnt/downloads"
STORAGE_MOUNT="/mnt/storage"
BACKUP_MOUNT="/mnt/backup"
```

## Services and Ports

| Service      | Default Port | URL                  |
| :----------- | :----------- | :------------------- |
| VPN          | N/A          | N/A                  |
| Jackett      | 9117         | http://<IP>:9117     |
| Sonarr       | 8989         | http://<IP>:8989     |
| Radarr       | 7878         | http://<IP>:7878     |
| Transmission | 9091         | http://<IP>:9091     |
| NZBGet       | 6789         | http://<IP>:6789     |
| Get IPlayer  | 1935         | http://<IP>:1935     |
| Jellyfin     | 8096         | http://<IP>:8096     |
| Watchtower   | N/A          | (No Web UI)          |

Generated URLs are saved to:

```
~/services_urls.txt
```

## How It Works

*   **VPN Routing**: All media applications route traffic through the VPN container. If the VPN disconnects, traffic is blocked for privacy.
*   **Tailscale**: Provides secure access to all services, bypassing the VPN when needed.
*   **Watchtower**: Automatically updates Docker containers.

## Testing

*   **Local Access**: Open `http://<local-IP>:<port>` in a browser.
*   **Tailscale Access**: Replace `<local-IP>` with your Tailscale IP.
*   **VPN Routing**: Verify traffic routes through the VPN:

    ```bash
    docker exec -it transmission curl ifconfig.me
    ```

*   **Logs**: Check Watchtower logs for updates:

    ```bash
    docker logs watchtower
    ```

## Troubleshooting

*   **VPN Issues**: Ensure PIA credentials are correct in `.env`. Check VPN logs:

    ```bash
    docker logs vpn
    ```

*   **Tailscale Authentication**:

    ```bash
    sudo tailscale up
    ```

## Contributing

Contributions are welcome! Open an issue or submit a pull request to enhance the project.

## License

This project is licensed under the MIT License.

## Acknowledgements

Special thanks to:

*   Docker
*   Gluetun VPN
*   LinuxServer.io
*   Sonarr
*   Radarr
*   Tailscale
