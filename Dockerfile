# syntax=docker/dockerfile:1
# === Piper MoveIt Docker [A1] ===
# Base = Tiryoh ros2-desktop-vnc:jazzy (Ubuntu 24.04 + ROS2 Jazzy + noVNC desktop on port 6080).
# noVNC integration: the base ENTRYPOINT is ["/bin/bash","-c","/entrypoint.sh"], which at
# runtime regenerates /etc/supervisor/conf.d/supervisord.conf and execs
# `tini -- supervisord -n -c /etc/supervisor/supervisord.conf`. The default supervisord.conf
# (from Ubuntu's `supervisor` pkg) includes /etc/supervisor/conf.d/*.conf. We therefore DO NOT
# override the base ENTRYPOINT; instead we drop a SEPARATELY-NAMED conf (ros-app.conf) into
# conf.d so it is loaded alongside the base's runtime-generated supervisord.conf without being
# clobbered. Our program runs /entrypoint.sh inside the VNC desktop session (DISPLAY=:1) so
# RViz renders into the noVNC desktop.

ARG BASE_IMAGE=ghcr.io/tiryoh/ros2-desktop-vnc:jazzy
FROM ${BASE_IMAGE}

# ---- Verified apt package set (SPEC §검증된 사실) ----
RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-jazzy-moveit \
        ros-jazzy-ros2-control \
        ros-jazzy-ros2-controllers \
        ros-jazzy-controller-manager \
        ros-jazzy-joint-trajectory-controller \
        ros-jazzy-joint-state-broadcaster \
        ros-jazzy-gripper-controllers \
        ros-jazzy-parallel-gripper-controller \
        ros-jazzy-robot-state-publisher \
        ros-jazzy-xacro \
        ros-jazzy-topic-tools \
        can-utils \
        ethtool \
        python3-pip \
        git \
    && rm -rf /var/lib/apt/lists/*

# ---- pyAgxArm (pinned by SHA) + python deps ----
ARG PYAGXARM_SHA=a226840db0c3d5c5dc7f3ec78d6cef1a6800f9e6
RUN git clone https://github.com/agilexrobotics/pyAgxArm.git /tmp/pyAgxArm \
    && cd /tmp/pyAgxArm \
    && git checkout ${PYAGXARM_SHA} \
    && pip3 install --break-system-packages . \
    && pip3 install --break-system-packages python-can scipy numpy \
    && rm -rf /tmp/pyAgxArm

# ---- Overlay workspace: build agx_arm_ros (pinned via submodule) ----
COPY ros2_ws/src /ws/src
# NOTE: NO --symlink-install. With symlinks the install/ env-hooks point into /ws/build;
# deleting /ws/build then dangles them and the packages become unfindable at runtime.
# Plain colcon build writes real files that survive removing build/log. (RV-build/test BLOCKER fix.)
RUN . /opt/ros/jazzy/setup.sh \
    && cd /ws \
    && colcon build \
    && rm -rf /ws/build /ws/log

# ---- noVNC-safe supervisor integration + entrypoint ----
COPY novnc/ros-app.conf /etc/supervisor/conf.d/ros-app.conf
# NOTE: must NOT be /entrypoint.sh — that path is the BASE's own script which launches
# supervisord (vnc+novnc). Overwriting it kills the desktop. Use a distinct name; ros-app.conf
# points supervisord's program at it. (RV-build/test BLOCKER fix.)
COPY entrypoint.sh /ros-app-entrypoint.sh
RUN chmod +x /ros-app-entrypoint.sh

# ---- Runtime defaults (SPEC env 계약) ----
ENV MODE=mock \
    ARM_TYPE=piper \
    EFFECTOR_TYPE=agx_gripper \
    CAN_IFACE=can0 \
    CAN_BITRATE=1000000 \
    LC_NUMERIC=C \
    ROS_DOMAIN_ID=0 \
    RMW_IMPLEMENTATION=rmw_fastrtps_cpp \
    FASTDDS_BUILTIN_TRANSPORTS=DEFAULT \
    ROS_STATIC_PEERS="" \
    ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET

# Keep the base ENTRYPOINT (supervisord launches noVNC + our ros-app program).
# CMD is the default MODE passed to our entrypoint via supervisord (see ros-app.conf,
# which reads $MODE). We still set CMD for documentation / direct `docker run` use.
CMD ["mock"]
