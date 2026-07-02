#!/usr/bin/env bash
# === Piper MoveIt Docker — entrypoint [A2 contract, authored under A1 for noVNC integration] ===
# Dispatches on MODE: mock (fake HW) / real (CAN) / dev (shell).
# Launched by supervisord (program:ros-app) so it coexists with the base's noVNC desktop.
# DISPLAY=:1 is provided by supervisord so RViz renders into the noVNC desktop (port 6080).

# NOTE: no `-u` — ROS setup.bash references unbound vars (AMENT_TRACE_SETUP_FILES) and would abort.
set -eo pipefail

# ---- Mode resolution: first CLI arg wins, else $MODE, else mock ----
MODE="${1:-${MODE:-mock}}"

ARM_TYPE="${ARM_TYPE:-piper}"
EFFECTOR_TYPE="${EFFECTOR_TYPE:-agx_gripper}"
CAN_IFACE="${CAN_IFACE:-can0}"
CAN_BITRATE="${CAN_BITRATE:-1000000}"

# ---- Locale fix (SPEC 함정: move_group needs C-locale-ish decimal parsing) ----
export LC_NUMERIC="${LC_NUMERIC:-C}"   # C locale uses '.' decimals → avoids move_group "expects a double" + no locale-gen needed

# ---- Always source ROS + overlay ----
# shellcheck disable=SC1091
source /opt/ros/jazzy/setup.bash
if [ -f /ws/install/setup.bash ]; then
    # shellcheck disable=SC1091
    source /ws/install/setup.bash
fi

# ---- Wait for the VNC desktop (DISPLAY :1) so RViz has somewhere to render ----
# The base brings up tigervnc on :1 via supervisord; it may not be ready the instant we start.
wait_for_display() {
    local disp="${DISPLAY:-:1}"
    local num="${disp#:}"
    num="${num%%.*}"
    local sock="/tmp/.X11-unix/X${num}"
    local i
    # 60s: in real mode the desktop is relocated to :2 by desktop-realfix (which runs last),
    # so the display can take longer to appear than the base's immediate :1.
    for i in $(seq 1 60); do
        if [ -S "${sock}" ]; then
            return 0
        fi
        echo "[entrypoint] waiting for X display ${disp} (${sock}) ... ${i}/60"
        sleep 1
    done
    echo "[entrypoint] WARN: X display ${disp} not detected after 60s; continuing anyway."
    return 0
}

# ---- real (host-network) renders to a non-conflicting X display ----
# In real mode the container shares the host network namespace (needed for host can0). If the
# host runs its own desktop on :1, the container VNC collides, so desktop-realfix.sh moves the
# desktop to :2. RViz must therefore render to :2 too (override the :1 supervisord passes in).
if [ "${MODE}" = "real" ]; then
    export DISPLAY=":2"
fi

echo "[entrypoint] MODE=${MODE} ARM_TYPE=${ARM_TYPE} EFFECTOR_TYPE=${EFFECTOR_TYPE} DISPLAY=${DISPLAY:-<unset>}"

case "${MODE}" in
    mock)
        wait_for_display
        echo "[entrypoint] launching MoveIt mock demo (mock_components/GenericSystem)..."
        exec ros2 launch agx_arm_moveit demo.launch.py \
            arm_type:="${ARM_TYPE}" \
            effector_type:="${EFFECTOR_TYPE}"
        ;;

    real)
        wait_for_display
        # Bring up CAN if we have privilege; tolerate already-up / no-permission.
        if ip link show "${CAN_IFACE}" >/dev/null 2>&1; then
            if ! ip -details link show "${CAN_IFACE}" | grep -q "state UP"; then
                echo "[entrypoint] bringing up ${CAN_IFACE} @ ${CAN_BITRATE} ..."
                # runs as user 'ubuntu' → use passwordless sudo (base grants it) for the privileged netlink op
                sudo ip link set "${CAN_IFACE}" up type can bitrate "${CAN_BITRATE}" \
                    || echo "[entrypoint] WARN: could not bring up ${CAN_IFACE} (privileged + host CAN needed). Continuing."
            else
                echo "[entrypoint] ${CAN_IFACE} already UP."
            fi
        else
            echo "[entrypoint] WARN: ${CAN_IFACE} not found. Ensure --network host + --privileged and host CAN is up."
        fi
        echo "[entrypoint] launching real MoveIt bring-up on ${CAN_IFACE}..."
        exec ros2 launch agx_arm_ctrl start_single_agx_arm_moveit.launch.py \
            can_port:="${CAN_IFACE}" \
            arm_type:="${ARM_TYPE}" \
            effector_type:="${EFFECTOR_TYPE}"
        ;;

    dev)
        echo "[entrypoint] dev mode: dropping into bash (env sourced). Build/launch manually in /ws."
        cd /ws 2>/dev/null || true
        exec bash
        ;;

    *)
        echo "[entrypoint] ERROR: unknown MODE='${MODE}' (expected: mock|real|dev)" >&2
        exit 2
        ;;
esac
