# 🐳 Docker Media Server Stack with VPN, Tailscale, and Media Management

This project simplifies the setup of a powerful Docker-based media server stack for Raspberry Pi and other Linux-based systems. It features secure VPN integration, Tailscale for remote access, and a suite of media management tools. The stack is designed for ease of use, scalability, and customization.

---

## 🌟 Features

- **VPN Integration**  
  Routes external traffic through a secure VPN container (powered by Gluetun).  

- **Tailscale Integration**  
  Provides secure remote access to your server and Docker containers.

- **Media Management Tools**  
  - 🐂 **Jackett**: Indexer proxy for torrent and Usenet sites.  
  - 🎥 **Radarr**: Movie downloader and organizer.  
  - 📺 **Sonarr**: TV show downloader and organizer.  
  - 🌐 **Transmission**: Torrent downloader.  
  - 📦 **NZBGet**: Usenet downloader.  
  - 📻 **Get IPlayer**: BBC iPlayer downloader with SonarrAutoImport.  
  - 🎧 **Lidarr**: Music download manager.  
  - 🎧 **Airsonic**: Personal media streamer for audio collections.  
  - 📖 **Audiobookshelf**: Audiobook and podcast server.  
  - 🔧 **Server Health Web Manager**: Web-based server monitoring and management tool.  
  - 🔄 **RTDClient**: Download manager for torrents.  
  - 🔹 **Jellyfin**: Media server for streaming.  

- **File Sharing**  
  - **Samba**: Cross-platform file sharing for Windows, macOS, and Linux.  
  - **NFS**: Lightweight file sharing for Linux-based environments.  

- **Automatic Updates**  
  Easily update your stack by pulling the latest `docker-compose.yml` from GitHub.  

- **Customizable**  
  Modify container names, ports, and settings through the `.env` file.

- **Watchtower**  
  Automatically updates Docker containers outside the VPN.

---

## 🛠️ Requirements

- Raspberry Pi (tested on Pi 5 with 8GB RAM) or a Linux-based system.  
- Docker and Docker Compose (automatically installed by the script).  
- Private Internet Access (PIA) as the VPN provider (support for more providers planned).  
- A Tailscale account for secure remote access.  

---

## 🚀 Installation

1. **Clone the Repository**  
   ```bash
   git clone https://github.com/Brownster/PI-PVR.git
   cd PI-PVR
   ```

2. **Make the Setup Script Executable**  
   ```bash
   chmod +x setup.sh
   ```

3. **Run the Setup Script**  
   ```bash
   ./setup.sh
   ```
   Follow the on-screen prompts to configure the environment, VPN, and file sharing.

---

## 🛠️ Configuration

### Environment Variables
The script generates a `.env` file for managing sensitive data. Edit this file to update your configuration:  
```bash
nano ~/docker/.env
```

Example `.env` file:
```plaintext
PIA_USERNAME=your_pia_username
PIA_PASSWORD=your_pia_password
TAILSCALE_AUTH_KEY=your_tailscale_auth_key
TIMEZONE=Europe/London
MOVIES_FOLDER="Movies"
TVSHOWS_FOLDER="TVShows"
DOWNLOADS="/mnt/storage/downloads"
```

---

## 📂 File Sharing

The script supports two sharing methods:  
- **Samba**: For cross-platform environments.  
- **NFS**: Recommended for Linux-only systems.  

Configure your preferred method during setup or edit the `.env` file.

---

## 🔄 Updates

Fetch the latest `docker-compose.yml` from GitHub and redeploy the stack:
```bash
./setup.sh --update
```

Ensure `DOCKER_COMPOSE_URL` in `.env` points to the correct URL.

---

## 🔦️ Services and Ports

| Service      | Default Port | URL                              |
|--------------|--------------|----------------------------------|
| VPN          | N/A          | N/A                              |
| Jackett      | 9117         | `http://<IP>:9117`               |
| Sonarr       | 8989         | `http://<IP>:8989`               |
| Radarr       | 7878         | `http://<IP>:7878`               |
| Transmission | 9091         | `http://<IP>:9091`               |
| NZBGet       | 6789         | `http://<IP>:6789`               |
| Get IPlayer  | 1935         | `http://<IP>:1935`               |
| Jellyfin     | 8096         | `http://<IP>:8096`               |
| Watchtower   | N/A          | (No Web UI)                      |

Generated URLs are saved to:  
`~/services_urls.txt`

---

## ⚙️ How It Works

- **VPN Routing**  
  All media apps route traffic through the VPN container. Traffic is blocked if the VPN disconnects.  

- **Tailscale**  
  Provides secure access to all services via your Tailscale IP.  

- **Watchtower**  
  Updates containers outside the VPN for unrestricted registry access.  

---

## 🧪 Testing

### Accessing Services:
- **Local Access**: `http://<local-IP>:<port>`  
- **Tailscale Access**: Replace `<local-IP>` with your Tailscale IP.

### Verify VPN Routing:
```bash
docker exec -it transmission curl ifconfig.me
```

### Logs:
- Watchtower logs for updates:
  ```bash
  docker logs watchtower
  ```
- VPN logs:
  ```bash
  docker logs vpn
  ```

---

## 🕸️ Troubleshooting

- **VPN Issues**:  
  - Ensure correct PIA credentials in `.env`.  
  - Check VPN logs:
    ```bash
    docker logs vpn
    ```

- **Tailscale Authentication**:  
  ```bash
  sudo tailscale up
  ```

---

## 🤝 Contributing

Contributions are welcome! Open an issue or submit a pull request to enhance the project.

---

## 📜 License

This project is licensed under the MIT License.

---

## 🙏 Acknowledgements

Special thanks to:  
- [Docker](https://www.docker.com)  
- [Gluetun VPN](https://github.com/qdm12/gluetun)  
- [LinuxServer.io](https://www.linuxserver.io)  
- [Sonarr](https://sonarr.tv)  
- [Radarr](https://radarr.video)  
- [Tailscale](https://tailscale.com)  

---

