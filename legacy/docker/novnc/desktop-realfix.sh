#!/usr/bin/env bash
# === Piper MoveIt Docker — real(host-network) desktop fix ===
# WHY THIS EXISTS:
#   The `real` profile runs with `network_mode: host` (required so the container can reach the
#   host's SocketCAN `can0`, which lives in the host network namespace). But host networking
#   also SHARES the host's X11 abstract-socket namespace:
#     1. If the host runs its own desktop on display :1, the container's VNC server (which the
#        base hardcodes to :1) collides → "Cannot establish any listening sockets" → vnc dies.
#     2. websockify can't bind privileged port 80 as user `ubuntu` under the host's netns
#        (host `net.ipv4.ip_unprivileged_port_start` is 1024) → noVNC dies.
#   Fix: move the container desktop to display :2 and serve noVNC on 6080 (same external port
#   as mock). RViz renders to :2 via entrypoint.sh exporting DISPLAY=:2 for real mode.
#
# The base ENTRYPOINT REGENERATES vnc_run.sh + conf.d/supervisord.conf (vnc/novnc on :1/port 80)
# on every start, so this can't be baked statically — we re-apply it at runtime. This program
# lives in conf.d/desktop-realfix.conf (the base never touches it) and is a no-op for every
# non-real profile (mock/dev/direct/gpu use a private netns where :1 and port 80 are fine).
#
# ROBUSTNESS: this program runs LAST (priority 1500, after vnc/novnc autostart at 999) so it is
# the sole owner of the desktop's final state — no race with supervisord's autostart. It STOPS
# vnc/novnc (clearing the FATAL state they hit on :1/port 80), cleans all stale VNC lock/pid/
# socket state, then STARTS them on :2/6080 with a verify+retry loop. (This is exactly the
# manual recovery sequence that brought the desktop up reliably during development.)

set -uo pipefail

MODE="${MODE:-mock}"
if [ "${MODE}" != "real" ]; then
    echo "[desktop-realfix] MODE=${MODE} (not real) → no-op."
    exit 0
fi

echo "[desktop-realfix] real mode → relocating desktop to display :2 + noVNC :6080"

# Wait for the supervisord control socket so supervisorctl works.
for i in $(seq 1 30); do
    [ -S /var/run/supervisor.sock ] && break
    sleep 1
done

clean_vnc_state() {
    # Remove every bit of stale per-display state a failed/old Xtigervnc :2 may have left.
    # (bracket pattern '[X]tigervnc' avoids pkill -f matching this script's own arg list)
    pkill -9 -f '[X]tigervnc :2' 2>/dev/null || true
    pkill -9 -f '[v]ncserver :2' 2>/dev/null || true
    rm -f /tmp/.X2-lock /tmp/.X11-unix/X2 \
          /home/ubuntu/.vnc/*:2.pid /home/ubuntu/.vnc/*:2.log 2>/dev/null || true
}

# 1) VNC server → display :2 (host uses :1). Keep the base's docker-commit lock-cleanup idiom.
cat > /home/ubuntu/.vnc/vnc_run.sh <<'EOF'
#!/bin/sh
[ -e /tmp/.X2-lock ] && rm -f /tmp/.X2-lock
[ -e /tmp/.X11-unix/X2 ] && rm -f /tmp/.X11-unix/X2
vncserver :2 -fg -geometry 1280x800 -depth 24
EOF
chown ubuntu:ubuntu /home/ubuntu/.vnc/vnc_run.sh
chmod +x /home/ubuntu/.vnc/vnc_run.sh

# 2) Desktop session → disable screen lock / blanking so the RViz desktop never locks to a
#    password prompt (an unattended kiosk-style desktop). gsettings runs in mate-session's dbus.
cat > /home/ubuntu/.vnc/xstartup <<'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
( sleep 8
  gsettings set org.mate.screensaver idle-activation-enabled false
  gsettings set org.mate.screensaver lock-enabled false
  gsettings set org.mate.session idle-delay 0
  xset s off -dpms ) >/dev/null 2>&1 &
mate-session
EOF
chown ubuntu:ubuntu /home/ubuntu/.vnc/xstartup
chmod +x /home/ubuntu/.vnc/xstartup

# 3) noVNC websockify → port 6080, forwarding to VNC :2 (rfbport 5902).
sed -i 's|websockify --web=/usr/lib/novnc 80 localhost:5901|websockify --web=/usr/lib/novnc 6080 localhost:5902|' \
    /etc/supervisor/conf.d/supervisord.conf

# 4) Reload definitions, then STOP both (clears the FATAL they hit on :1/port 80 at autostart).
supervisorctl reread || true
supervisorctl update || true
supervisorctl stop vnc novnc >/dev/null 2>&1 || true
clean_vnc_state

# 5) noVNC up (6080/5902).
supervisorctl start novnc >/dev/null 2>&1 || true

# 6) VNC up on :2 with verify+retry — the only deterministic way past stale-lock / race flakiness.
ok=0
for attempt in 1 2 3 4 5; do
    supervisorctl start vnc >/dev/null 2>&1 || true
    sleep 4
    if [ -S /tmp/.X11-unix/X2 ]; then
        ok=1
        echo "[desktop-realfix] VNC :2 up (attempt ${attempt})"
        break
    fi
    echo "[desktop-realfix] VNC :2 not up yet (attempt ${attempt}) — cleaning + retrying"
    supervisorctl stop vnc >/dev/null 2>&1 || true
    clean_vnc_state
    sleep 1
done

if [ "${ok}" -eq 1 ]; then
    echo "[desktop-realfix] done — desktop on :2, noVNC on http://localhost:6080"
else
    echo "[desktop-realfix] WARN: VNC :2 did not come up after 5 attempts; check vnc logs."
fi
exit 0
