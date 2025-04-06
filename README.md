☠️ Ahoy! The Raspberry Pi Docker Stack o’ the High Seas (With VPN, Tailscale, & Media Management) ☠️

Avast, ye scurvy seadogs! This here treasure chest o’ a project be hoistin’ a Docker-based media server stack on yer Raspberry Pi or any Linux-based vessel. We’ve got VPN rigging, Tailscale fer secure remote access, an' a fine haul of media management tools. All be highly customizable, deployable with Docker Compose, an' kept shipshape via GitHub updates—like a well-trained parrot! 🦜
⚓️ Features

    VPN Integration: Arr, routes all yer external traffic through a secure VPN container (powered by Gluetun).

    Tailscale: Hoist the Tailscale sails fer secure remote access to yer server an’ Docker containers by their Tailscale IP.

    Media Management Tools:

        🗂️ Jackett: Indexer proxy fer them torrent an’ Usenet sites.

        🎥 Radarr: Manages yer movie booty.

        📺 Sonarr: Keeps yer TV shows in line.

        🌐 Transmission: Torrent downloader to snag yer treasures.

        📦 NZBGet: Hauls in yer Usenet plunder.

        📻 Get IPlayer: Downloads BBC iPlayer bounty, complete with SonarrAutoImport.

        🎛️ Jellyfin: Aye, a slick media server fer streamin’ all yer loot.

    Watchtower: Auto-updates Docker containers outside the VPN—no scurvy containers here!

    File Sharing:

        Samba fer Windows/macOS/Linux, or

        NFS fer yer Linux-only fleets.

    Customizable: Rename containers, change ports, tweak settings—arr, do as ye please!

    Automatic Updates: Pulls the latest docker-compose.yml from GitHub an’ redeploys with a single command. Shiver me timbers!

image
🏴‍☠️ Requirements

    A Raspberry Pi or Linux-based rig (tested on Raspberry Pi 5 with 8GB o’ RAM).

    Docker an’ Docker Compose installed (our script can handle that, me hearties!).

    Private Internet Access (PIA) as VPN provider (coming soon: AirVPN, Mullvad, NordVPN, etc. — the whole pirate fleet!).

    A Tailscale account fer secure remote boardin’.

⚙️ Installation
Option 1: Command Line Installation

    Clone this repository into yer treasure hold:

git clone https://github.com/Brownster/PI-PVR.git
cd PI-PVR

Make the setup script executable:

chmod +x pi-pvr.sh

Run the setup script:

    ./pi-pvr.sh

    Answer the script’s questions, set up yer environment, VPN, an’ file sharing like a true pirate captain.

Option 2: Web-Based Installation (Recommended)

Fer a swashbucklin’ web-based method:

chmod +x web-install.sh
./web-install.sh

This spins up a fancy web installer at http://<your-pi-ip>:8080 so ye can:

    Configure all yer settings through a friendly pirate interface

    Watch installation progress in real-time

    Easily reconfigure yer rig after installation

    Access a dashboard to manage yer media loot

Alternatively, run:

chmod +x pi-pvr.sh
./pi-pvr.sh --web-installer

to set sail with the web-based route.
🏴 Usage
Debug Mode

Need extra logs, ye say? Hoist the --debug flag:

./pi-pvr.sh --debug

Update Docker Compose Stack

Fetch the latest docker-compose.yml from GitHub an’ redeploy the whole armada:

./pi-pvr.sh --update

⚓ Configuration
Environment Variables

The script crafts an .env file to stash yer secrets. Ye can open it up an’ edit:

nano ~/docker/.env

Example:

PIA_USERNAME=yer_pia_username
PIA_PASSWORD=yer_pia_password
TAILSCALE_AUTH_KEY=yer_tailscale_auth_key
TIMEZONE=Europe/London
MOVIES_FOLDER="Movies"
TVSHOWS_FOLDER="TVShows"
DOWNLOADS="/mnt/storage/downloads"

File Sharing

Choose yer poison:

    Samba: Cross-platform for all the landlubbers out there.

    NFS: Linux-only, for the stouthearted.

Configure it durin’ setup or edit yer .env.
Updating from GitHub

Set DOCKER_COMPOSE_URL in yer .env to link to yer docker-compose.yml on GitHub:

DOCKER_COMPOSE_URL=https://raw.githubusercontent.com/yourusername/yourrepo/main/docker-compose.yml

🏴‍☠️ Services and Ports
Service	Default Port	URL
VPN	N/A	N/A
Jackett	9117	http://<IP>:9117
Sonarr	8989	http://<IP>:8989
Radarr	7878	http://<IP>:7878
Transmission	9091	http://<IP>:9091
NZBGet	6789	http://<IP>:6789
Get IPlayer	1935	http://<IP>:1935
Jellyfin	8096	http://<IP>:8096
Watchtower	N/A	(No Web UI)

When these beauties be up an’ runnin’, ye’ll find the URLs in:

~/services_urls.txt

☠️ How It Works

    VPN Routing: All yer media scallywags route traffic through the VPN container. If it disconnects, the traffic be scuppered for privacy!

    Tailscale: Provides a secure passage to yer services, sidesteppin’ the VPN if needed.

    Watchtower: Auto-updates Docker containers outside the VPN so the scurvy Docker registry can be reached.

🏴‍☠️ Testing

    Local Access: Point yer browser to http://<local-IP>:<port>.

    Tailscale Access: Replace <local-IP> with yer Tailscale IP.

    VPN Routing: Check that Transmission's traffic be goin’ through the VPN:

docker exec -it transmission curl ifconfig.me

Logs: Keep an eye on yer Watchtower logs:

    docker logs watchtower

🔧 Troubleshooting

    VPN Woes: Confirm yer PIA username/password in .env or check the VPN logs:

docker logs vpn

Tailscale Authentication:

    sudo tailscale up

🤝 Contributing

All pirates be welcome! Open an issue or cast a pull request into the briny deep to improve this project.
🏴‍☠️ License

This project sails under the MIT License flag. Hoist it high, me mateys!
🎉 Acknowledgements

Raise a tankard o’ grog to:

    Docker

    Gluetun VPN

    LinuxServer.io

    Sonarr

    Radarr

    Tailscale

Now set sail, ye sea dogs, an’ enjoy the spoils of yer Docker-based media treasure trove! 🏴‍☠️

The Docker Shanty
(To be roared at full volume ‘round the mast!)

Verse 1
Oh, we set sail on a Pi so wee,
With Docker images bold and free,
Gluetun VPN’s the guardin’ mate,
Keeps our secrets locked behind the gate!
Jellyfin streams across the foam,
Arr, it’s the best sea-video home!

Chorus
Yo-ho-ho, a Docker we’ll run!
Jackett, Radarr, Transmission for fun!
Raise the Tailscale flag, let’s roam the seas,
Our PVR’s a pirate’s breeze!

Verse 2
Sonarr fetches the shows to see,
While NZBGet hauls from the news so free,
The Samba share be stowed below,
Where the scallywags drop their spoils in tow!
Watchtower’s perched up high on the mast,
Updates quick with a mighty blast!

(Repeat Chorus)
Yo-ho-ho, a Docker we’ll run!
Jackett, Radarr, Transmission for fun!
Raise the Tailscale flag, let’s roam the seas,
Our PVR’s a pirate’s breeze!

Verse 3
In the web installer’s harbor we rest,
Setting up apps that pass every test,
We rummage for logs in hidden stows,
If trouble brews, we tweak as it goes!
From Pi to Pi, our legend shall spread,
“Arr, the Pi-PVR’s best!” they said!

(Final Chorus)
Yo-ho-ho, a Docker we’ll run!
Jackett, Radarr, Transmission for fun!
Raise the Tailscale flag, let’s roam the seas,
Our PVR’s a pirate’s breeze!
Our PVR’s a pirate’s breeeeze!

Yo-ho! 🏴‍☠️
