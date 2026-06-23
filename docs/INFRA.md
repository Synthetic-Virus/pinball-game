# Infrastructure Runbook
Owner: devops-engineer. How the pinball project builds and deploys. The laptop holds NO
Godot and NO build tooling; everything heavy runs on a homelab self-hosted runner, triggered by
`git push`.

## Topology
- Laptop (WSL): code editing by agents + git. Optional: gdtoolkit (pure-Python lint) for fast checks.
- GitHub (private repo Synthetic-Virus/pinball-game): code, CI/CD workflows, Git LFS (later).
- Homelab Docker host: the self-hosted runner container (Godot headless + templates + steamcmd + gdtoolkit), label `godot`.
- Homelab web host: serves the demo URL; `main` pushes rsync the web build here.
- Steam: stubbed until a Steamworks App ID exists.

## 1. Provision the build runner (one time)
Pick a Docker host with spare CPU (decided at setup). Then on that host:
```
# from a checkout of this repo:
cd ci/runner
cp .env.example .env
# mint a registration token (run anywhere with gh authed as the repo owner):
gh api -X POST repos/Synthetic-Virus/pinball-game/actions/runners/registration-token --jq .token
# paste it into .env as RUNNER_TOKEN, then:
docker compose up -d --build
```
Confirm the runner shows up: Settings -> Actions -> Runners (or `gh api repos/Synthetic-Virus/pinball-game/actions/runners`).
IMPORTANT: confirm GODOT_VERSION in Dockerfile/compose matches the latest stable 4.x and project.godot.

## 2. Generate export presets (one time)
The deploy/release workflows need presets named exactly "Web", "Windows Desktop", and "Linux/X11".
Easiest: open the project once in the Godot editor (on any machine with Godot) and define them, OR
have devops-engineer generate export_presets.cfg and verify it on the runner. Commit
export_presets.cfg. Install the matching export templates in the runner image (already handled by
the Dockerfile).

## 3. Web demo target (one time)
On the homelab web host, create a web root served at the demo URL (for example a Caddy/nginx vhost at
pinball.virusgaming.org or an internal hostname). Then add the repo secret:
```
gh secret set DEMO_DEPLOY_TARGET --repo Synthetic-Virus/pinball-game --body 'deploy@webhost:/srv/www/pinball-demo/'
```
The runner needs an SSH key authorized to that target (mount it into the runner or use an agent).
After this, every push to main publishes the latest playable build to that URL.

## 4. Git LFS (only when binary assets land)
The gray-box prototype has no binaries, so do not install git-lfs yet (keeps the laptop lean).
When the first art/audio asset is committed: `git lfs install` on whatever machine commits assets,
then `git add .gitattributes` is already done; commit the asset normally.

## 5. Enabling Steam later
1. Buy a Steamworks app (about USD 100), get the App ID and depot IDs.
2. Add repo secrets: STEAM_APP_ID, STEAM_BUILD_ACCOUNT, STEAM_CONFIG_VDF (the Steam Guard config),
   and depot IDs.
3. In .github/workflows/release.yml change the steam job `if: false` to `if: ${{ vars.STEAM_ENABLED == 'true' }}`
   and set the repo variable STEAM_ENABLED=true.
4. The persistent self-hosted runner keeps the Steam login alive across builds (steamcmd sentry),
   which is why Steam deploys run there and not on ephemeral hosted runners.

## 6. Public URL via Cloudflare Tunnel (pinball.virusgaming.org)
The demo is served by nginx on the VM at :8080 on the LAN. To expose it publicly over HTTPS with no
port-forwarding, a `cloudflared` connector runs in the compose (profile: tunnel) and connects to a
Cloudflare-managed tunnel. Steps:
1. Cloudflare Zero Trust dashboard -> Networks -> Tunnels -> Create a tunnel (Cloudflared). Name it
   e.g. "gamedev". Choose the Docker option and COPY the connector TOKEN (the long eyJ... string).
2. In that tunnel add a Public Hostname:
     Subdomain: pinball   Domain: virusgaming.org
     Service: HTTP   URL: demo-web:80
   (cloudflared shares the compose network, so it resolves the nginx container named "demo-web".)
3. On the VM put the token in ~/pinball-runner/.env as  CF_TUNNEL_TOKEN=eyJ...
4. cd ~/pinball-runner && sudo docker compose --profile tunnel up -d
5. pinball.virusgaming.org goes live over HTTPS; Cloudflare auto-manages the DNS.
Image pinned to cloudflare/cloudflared:2026.6.0 (bump deliberately, never :latest).
