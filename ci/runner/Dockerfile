# Self-hosted GitHub Actions runner image for Godot 4 game builds.
# Runs on a homelab Docker host so ALL build tooling stays off the laptop.
# Layers Godot headless + export templates + steamcmd + gdtoolkit on a maintained runner base.
#
# PROVISION-TIME TODO (gamedev-devops-engineer): confirm GODOT_VERSION matches the latest stable
# 4.x AND the project's config/features in project.godot. Export templates MUST match exactly.
ARG RUNNER_BASE=myoung34/github-runner:latest
FROM ${RUNNER_BASE}

ARG GODOT_VERSION=4.3.1
ENV GODOT_VERSION=${GODOT_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends       wget unzip rsync ca-certificates python3 python3-pip  && pip3 install --no-cache-dir "gdtoolkit==4.*"  && rm -rf /var/lib/apt/lists/*

# Godot headless (the standard Linux binary supports --headless) + matching export templates.
RUN set -eux;     base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable";     wget -q "$base/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip;     unzip /tmp/godot.zip -d /tmp;     mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot;     chmod +x /usr/local/bin/godot;     wget -q "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" -O /tmp/templates.tpz;     mkdir -p "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable";     unzip /tmp/templates.tpz -d /tmp/tpl;     mv /tmp/tpl/templates/* "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/";     rm -rf /tmp/godot.zip /tmp/templates.tpz /tmp/tpl

# steamcmd for future Steam deploys (stubbed until an App ID exists).
RUN dpkg --add-architecture i386 || true;     apt-get update && apt-get install -y --no-install-recommends lib32gcc-s1 || true;     rm -rf /var/lib/apt/lists/*;     mkdir -p /opt/steamcmd && cd /opt/steamcmd;     wget -q https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz;     tar -xzf steamcmd_linux.tar.gz && rm steamcmd_linux.tar.gz

RUN godot --headless --version || true
