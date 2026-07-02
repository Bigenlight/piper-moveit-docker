#!/usr/bin/env bash
# run-mock.sh — 검증된 mock(가짜 하드웨어) MoveIt 데모 원커맨드 실행.
#
# 실물 CAN 어댑터 없이 mock_components/GenericSystem 으로 팔+그리퍼를 흉내낸다.
# 이게 이 리포의 매일 쓰는 경로. 실기계는 scripts/run-real.sh 참고.
#
# Usage:
#   ./scripts/run-mock.sh
#   ARM_TYPE=piper EFFECTOR_TYPE=agx_gripper ./scripts/run-mock.sh   # env 로 오버라이드
#
# LC_NUMERIC=C 는 로케일이 소수점을 ','로 쓰면 move_group 이 "expects a double" 로
# 죽는 걸 막는다(C 로케일 = '.' 소수점). 이 호스트엔 en_US.UTF-8 이 없어서 여기 명시.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WS="$REPO_ROOT/ros2_ws"

# 1) ROS 2 Jazzy 환경
source /opt/ros/jazzy/setup.bash

# 2) 워크스페이스 오버레이 (없으면 셋업부터)
if [ ! -f "$WS/install/setup.bash" ]; then
  echo "install/ 없음 → scripts/setup-native.sh 먼저 돌려서 colcon build 해라." >&2
  exit 1
fi
source "$WS/install/setup.bash"

# 3) versions.env 기본값 로드 (ARM_TYPE/EFFECTOR_TYPE). 호출자가 미리 넣은 env 가 이김.
_ARM_OVERRIDE="${ARM_TYPE:-}"
_EFF_OVERRIDE="${EFFECTOR_TYPE:-}"
if [ -f "$REPO_ROOT/versions.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$REPO_ROOT/versions.env"
  set +a
fi
[ -n "$_ARM_OVERRIDE" ] && ARM_TYPE="$_ARM_OVERRIDE"
[ -n "$_EFF_OVERRIDE" ] && EFFECTOR_TYPE="$_EFF_OVERRIDE"

# 4) 런치. ~30초 후 "You can start planning now!" 로그 뜨면
#    런치가 띄운 로컬 RViz 창에서 조작하면 된다.
#    (mock 피드백 토픽은 /control/joint_states — 실기계의 /feedback/joint_states 와 다름)
exec env LC_NUMERIC=C ros2 launch agx_arm_moveit demo.launch.py \
  arm_type:="${ARM_TYPE:-piper}" \
  effector_type:="${EFFECTOR_TYPE:-agx_gripper}"
