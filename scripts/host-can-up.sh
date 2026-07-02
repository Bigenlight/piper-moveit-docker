#!/usr/bin/env bash
# host-can-up.sh — 실물 Piper 용 호스트 SocketCAN 인터페이스 올리기.
#
# 네이티브 real 런치(run-real.sh / ros2 launch agx_arm_ctrl start_single_agx_arm_moveit.launch.py ...)
# 전에 호스트에서 먼저 sudo 로 실행해라. 이게 gs_usb 올리고 can0 를 1Mbps 로 세팅함.
# AgileX Piper 는 gs_usb 커널 드라이버로 잡히는 USB-CAN 어댑터를 쓴다.
#
# 사용법:
#   sudo ./scripts/host-can-up.sh [IFACE] [BITRATE]
#   sudo CAN_IFACE=can0 CAN_BITRATE=1000000 ./scripts/host-can-up.sh
#
# 기본값은 versions.env / SPEC 과 일치: iface=can0, bitrate=1000000 (1 Mbit/s).
set -euo pipefail

IFACE="${1:-${CAN_IFACE:-can0}}"
BITRATE="${2:-${CAN_BITRATE:-1000000}}"

if [ "$(id -u)" -ne 0 ]; then
  echo "경고: root 가 아니라 'ip link set ... up' 이 십중팔구 실패한다." >&2
  echo "      이렇게 다시 실행해: sudo $0 $IFACE $BITRATE" >&2
fi

echo "==> gs_usb 커널 모듈(USB-CAN 드라이버) 로드 중"
if ! modprobe gs_usb; then
  echo "경고: 'modprobe gs_usb' 실패 — 일단 계속 진행한다." >&2
  echo "      (드라이버가 빌트인이거나 이미 로드됐거나, 어댑터가 안 꽂혀 있을 수 있음)" >&2
fi

echo "==> ${IFACE} 를 CAN @ ${BITRATE} bit/s 로 올리는 중"
# 먼저 down: 이미 UP 이면(이전 실행 / 잘못된 보율) UP 상태로 재설정할 때
# "Device or resource busy" 로 실패한다. AgileX 의 can_activate.sh 도 똑같이 함.
# 인터페이스가 아직 없어도 그냥 넘어가게 둔다.
ip link set "${IFACE}" down 2>/dev/null || true
ip link set "${IFACE}" up type can bitrate "${BITRATE}"
# TX 큐 키우기: Piper 한 대가 초당 수천 프레임을 쏘는데, 기본 txqueuelen(10)이면
# 버스트 때 프레임을 흘린다. best-effort (미지원이면 무시).
ip link set "${IFACE}" txqueuelen 65536 2>/dev/null || true

echo "==> 인터페이스 상태:"
ip -details link show "${IFACE}"

cat <<EOF

==> ${IFACE} 올라옴. 트래픽 확인은 이걸로:
      candump ${IFACE}
    (설치: sudo apt install can-utils)

    나중에 다시 내리려면:
      sudo ip link set ${IFACE} down
EOF

# ----------------------------------------------------------------------------
# (선택) 부팅 시 / 어댑터 꽂을 때 자동으로 올리기
# ----------------------------------------------------------------------------
# 1) udev 규칙 — 어댑터에 고정 이름을 주고 설정을 트리거.
#    /etc/udev/rules.d/90-piper-can.rules 생성:
#
#      # gs_usb CAN 어댑터를 매칭해서 "can0" 라는 고정 이름을 줌
#      SUBSYSTEM=="net", ACTION=="add", DRIVERS=="gs_usb", NAME="can0"
#
#    그다음: sudo udevadm control --reload-rules && sudo udevadm trigger
#
# 2) systemd-networkd — 보율 + 자동 up 을 선언적으로 설정.
#    /etc/systemd/network/80-can0.network 생성:
#
#      [Match]
#      Name=can0
#
#      [CAN]
#      BitRate=1000000
#
#    활성화: sudo systemctl enable --now systemd-networkd
#    (systemd-networkd 가 can0 이 나타날 때마다 보율을 잡고 자동으로 올려줘서,
#     이 스크립트를 수동으로 돌릴 필요가 없어진다.)
# ----------------------------------------------------------------------------
