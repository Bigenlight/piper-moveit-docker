#!/usr/bin/env bash
# run-real.sh — 실물 AgileX Piper 를 네이티브 ROS 2 Jazzy 로 브링업하는 래퍼.
#
# ⚠️  미검증 (docker 패리티 기준). 지금 이 호스트엔 CAN 어댑터가 안 붙어 있어서
#     네이티브로 직접 돌려본 적이 없어요. 아래 런치 커맨드는 서브모듈 런치 파일
#     (agx_arm_ctrl/start_single_agx_arm_moveit.launch.py) 과 구 docker real 프로파일을
#     대조해서 맞춘 것. 실물에 물리기 전에 반드시 docs/real-robot-checklist.md 를
#     먼저 정독할 것 (24V 전원 / M5 마운트 / 626mm 리치 / 페이로드 / E-stop / 펌웨어).
#
# 사용법:
#   1) 먼저 호스트에서 CAN 을 올린다 (sudo 필요):
#        sudo ./scripts/host-can-up.sh
#   2) 그 다음 이 스크립트 (sudo 아님):
#        ./scripts/run-real.sh
#
#   iface/arm/effector 는 versions.env 값(CAN_IFACE/ARM_TYPE/EFFECTOR_TYPE)을 따르고,
#   env 로 덮어쓸 수 있어요:
#        CAN_IFACE=can0 ARM_TYPE=piper EFFECTOR_TYPE=agx_gripper ./scripts/run-real.sh
#
# ⚠️  안전 주의 (실물):
#   - 이 런치는 auto_enable=true 가 기본이라 브링업 직후 팔이 즉시 STIFF(토크 인가)
#     상태가 됩니다. 팔 주변을 비우고 시작하세요. 이 로봇엔 **물리 E-stop 이 없으니**,
#     한 사람이 24V 전원 커넥터에 손을 올리고 즉시 뽑을 준비를 한 채로 시작하세요
#     (소프트 정지는 /emergency_stop 서비스 = 현재 자세 유지).
#   - speed_percent 기본값은 100 입니다. 첫 모션은 반드시 낮은 속도(~20)로,
#     그리고 RViz 의 MoveIt Plan & Execute (계획→검토→실행) 로만 움직이세요.
#     joint 를 직접 커맨드로 튀기지 말 것. 속도를 낮추려면 런치에
#     speed_percent:=20 인자를 추가하면 됩니다.
set -e

# 리포 루트 (이 스크립트의 상위 디렉터리)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- ROS 2 환경 소싱 (run-mock 과 동일한 가드) ------------------------------
JAZZY_SETUP="/opt/ros/jazzy/setup.bash"
WS_SETUP="${REPO_ROOT}/ros2_ws/install/setup.bash"

if [ ! -f "${JAZZY_SETUP}" ]; then
  echo "ERROR: ${JAZZY_SETUP} 가 없어요. ROS 2 Jazzy 가 설치돼 있나요?" >&2
  exit 1
fi
if [ ! -f "${WS_SETUP}" ]; then
  echo "ERROR: ${WS_SETUP} 가 없어요. 워크스페이스를 먼저 빌드하세요:" >&2
  echo "       cd ros2_ws && source /opt/ros/jazzy/setup.bash && colcon build --symlink-install" >&2
  echo "       (또는 ./scripts/setup-native.sh)" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${JAZZY_SETUP}"
# shellcheck disable=SC1090
source "${WS_SETUP}"

# --- CAN 인터페이스 확인 ----------------------------------------------------
CAN_IFACE="${CAN_IFACE:-can0}"
if ! ip -details link show "${CAN_IFACE}" 2>/dev/null | grep -q 'state UP'; then
  echo "ERROR: CAN 인터페이스 '${CAN_IFACE}' 가 UP 상태가 아니에요." >&2
  echo "       sudo ./scripts/host-can-up.sh 를 먼저 실행하세요." >&2
  exit 1
fi

# --- 실물 브링업 ------------------------------------------------------------
# LC_NUMERIC=C: C 로케일은 소수점을 '.' 로 쓰므로 move_group 의
#   "expects a double" 파싱 오류를 피함 (이 호스트엔 en_US.UTF-8 미생성).
ARM_TYPE="${ARM_TYPE:-piper}"
EFFECTOR_TYPE="${EFFECTOR_TYPE:-agx_gripper}"

echo "==> real 브링업: can_port=${CAN_IFACE} arm_type=${ARM_TYPE} effector_type=${EFFECTOR_TYPE}"
echo "    (auto_enable 기본 true → 팔이 곧 STIFF. speed_percent 기본 100 → 첫 모션은 낮게.)"
echo "    ~30초 뒤 로그에 'You can start planning now!' 가 뜨면 RViz 에서 Plan & Execute."

exec env LC_NUMERIC=C ros2 launch agx_arm_ctrl start_single_agx_arm_moveit.launch.py \
  can_port:="${CAN_IFACE}" \
  arm_type:="${ARM_TYPE}" \
  effector_type:="${EFFECTOR_TYPE}"
