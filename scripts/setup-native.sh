#!/usr/bin/env bash
# setup-native.sh — piper-moveit 네이티브 ROS 2 Jazzy 셋업 재현 스크립트.
#
# 프레시 클론에서 mock 데모가 뜰 때까지의 검증된 절차를 그대로 자동화한다.
# (구 Docker 시절의 Dockerfile + README '로컬 빌드' 섹션의 네이티브 대체본.
#  docker 원본은 legacy/docker/ 참고.)
#
# 하는 일:
#   ① 전제 확인      : /opt/ros/jazzy 존재 + uname -m = x86_64
#   ② apt 설치       : MoveIt2 + ros2_control 스택 + xacro/topic-tools + can-utils 등
#   ③ 서브모듈       : git submodule update --init --recursive
#                      (versions.env 의 AGX_ARM_ROS_SHA 와 실제 gitlink 대조)
#   ④ pyAgxArm       : PYAGXARM_SHA 로 checkout 후 pip3 install --user --break-system-packages
#   ⑤ colcon build   : ros2_ws 를 --symlink-install 로 빌드
#   ⑥ 안내           : scripts/run-mock.sh 포인터
#
# 재실행 안전(멱등 지향): apt 는 이미 설치돼 있으면 넘어가고, 서브모듈/pip/colcon 도 반복 실행 가능.
#
# 사용:
#   ./scripts/run-mock.sh   ← 이 스크립트로 준비 끝난 뒤 실행
#   ./scripts/setup-native.sh
set -euo pipefail

# --- 경로 잡기 (스크립트 위치 기준 상대경로) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_ENV="${REPO_ROOT}/versions.env"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# --- versions.env 로드 (핀 SHA + 런타임 기본값) ---
[ -f "${VERSIONS_ENV}" ] || die "versions.env 를 못 찾았어: ${VERSIONS_ENV}"
set -a
# shellcheck disable=SC1090
. "${VERSIONS_ENV}"
set +a

# =========================================================================
say "① 전제 확인"
# =========================================================================
ARCH="$(uname -m)"
if [ "${ARCH}" != "x86_64" ]; then
  die "이 셋업은 x86_64 에서 검증됨. 지금 아키텍처는 '${ARCH}' 라 중단할게.
       (다른 아키텍처면 ROS 2 Jazzy 바이너리/파이썬 휠 호환을 직접 확인해야 해.)"
fi

if [ ! -d /opt/ros/jazzy ]; then
  cat >&2 <<'EOF'
ERROR: /opt/ros/jazzy 가 없어. 먼저 호스트에 ROS 2 Jazzy 를 설치해야 해.
       (ros-jazzy-desktop 권장 — rviz2/colcon/rosdep 포함)

  설치 가이드: https://docs.ros.org/en/jazzy/Installation/Ubuntu-Install-Debs.html
  요약:
    sudo apt update && sudo apt install -y software-properties-common curl
    sudo add-apt-repository universe
    sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      -o /usr/share/keyrings/ros-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
      http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
      | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
    sudo apt update && sudo apt install -y ros-jazzy-desktop

  설치 후 이 스크립트를 다시 돌려줘.
EOF
  exit 1
fi
echo "  OK: /opt/ros/jazzy 존재, 아키텍처 ${ARCH}"

# =========================================================================
say "② apt 패키지 설치 (sudo 필요)"
# =========================================================================
APT_PKGS=(
  ros-jazzy-moveit
  ros-jazzy-ros2-control
  ros-jazzy-ros2-controllers
  ros-jazzy-controller-manager
  ros-jazzy-joint-trajectory-controller
  ros-jazzy-joint-state-broadcaster
  ros-jazzy-gripper-controllers
  ros-jazzy-parallel-gripper-controller
  ros-jazzy-robot-state-publisher
  ros-jazzy-xacro
  ros-jazzy-topic-tools
  can-utils
  ethtool
  python3-pip
  git
)

APT_CMD=(sudo apt-get install -y --no-install-recommends "${APT_PKGS[@]}")
echo "  실행: ${APT_CMD[*]}"
if ! "${APT_CMD[@]}"; then
  warn "apt 설치가 실패했어(비대화형/네트워크/권한 문제일 수 있음)."
  cat >&2 <<EOF

  아래 명령을 수동으로 한 번 돌려보고, 성공하면 이 스크립트를 다시 실행해:

    sudo apt-get update
    ${APT_CMD[*]}

EOF
  printf '이대로 다음 단계(서브모듈/pip/colcon)를 계속할까? [y/N] '
  read -r reply || reply=""
  case "${reply}" in
    [yY]|[yY][eE][sS]) echo "  계속 진행할게 (설치가 덜 됐으면 이후 단계가 실패할 수 있음)." ;;
    *) die "apt 설치를 마친 뒤 다시 실행해줘." ;;
  esac
fi

# =========================================================================
say "③ git 서브모듈 초기화 + 핀 대조"
# =========================================================================
git -C "${REPO_ROOT}" submodule update --init --recursive

SUBMODULE_DIR="${REPO_ROOT}/ros2_ws/src/agx_arm_ros"
if [ -d "${SUBMODULE_DIR}/.git" ] || [ -f "${SUBMODULE_DIR}/.git" ]; then
  ACTUAL_SHA="$(git -C "${SUBMODULE_DIR}" rev-parse HEAD)"
  EXPECTED_SHA="${AGX_ARM_ROS_SHA:-}"
  if [ -n "${EXPECTED_SHA}" ] && [ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]; then
    warn "agx_arm_ros 서브모듈 SHA 가 versions.env 핀과 달라!
         versions.env : ${EXPECTED_SHA}
         실제 HEAD     : ${ACTUAL_SHA}
       (.gitmodules 가 branch=ros2 floating 이라 벌어질 수 있음. 재현성이 필요하면
        git -C ros2_ws/src/agx_arm_ros checkout ${EXPECTED_SHA} 로 맞춰줘.)"
  else
    echo "  OK: agx_arm_ros @ ${ACTUAL_SHA} (versions.env 핀과 일치)"
  fi
else
  warn "${SUBMODULE_DIR} 가 서브모듈로 초기화되지 않은 것 같아 — 위 update 로그 확인해줘."
fi

# =========================================================================
say "④ pyAgxArm (PYAGXARM_SHA 핀) + python-can 설치"
# =========================================================================
# *** PEP668: Ubuntu 24.04 는 externally-managed 라 --user 만으로는 거부됨.
#     반드시 --user AND --break-system-packages 둘 다. sudo 아님(→ ~/.local 에 설치). ***
[ -n "${PYAGXARM_SHA:-}" ] || die "versions.env 에 PYAGXARM_SHA 가 없어."

PYAGX_TMP="$(mktemp -d)"
cleanup() { rm -rf "${PYAGX_TMP}"; }
trap cleanup EXIT

echo "  clone: https://github.com/agilexrobotics/pyAgxArm.git → ${PYAGX_TMP}"
git clone https://github.com/agilexrobotics/pyAgxArm.git "${PYAGX_TMP}/pyAgxArm"
git -C "${PYAGX_TMP}/pyAgxArm" checkout "${PYAGXARM_SHA}"
echo "  pyAgxArm @ $(git -C "${PYAGX_TMP}/pyAgxArm" rev-parse HEAD)"

pip3 install --user --break-system-packages "${PYAGX_TMP}/pyAgxArm"
pip3 install --user --break-system-packages python-can

# =========================================================================
say "⑤ colcon build (--symlink-install)"
# =========================================================================
# shellcheck disable=SC1091
source /opt/ros/jazzy/setup.bash
(
  cd "${REPO_ROOT}/ros2_ws"
  colcon build --symlink-install
)

# =========================================================================
say "⑥ 완료!"
# =========================================================================
cat <<EOF

  준비 끝났어. 이제 mock 데모를 띄우려면:

    ./scripts/run-mock.sh

  (내부적으로 아래를 실행함 — ~30초 뒤 "You can start planning now!" 로그가 뜨면 RViz 로컬 창에서 계획 시작 가능)
    source /opt/ros/jazzy/setup.bash
    source "${REPO_ROOT}/ros2_ws/install/setup.bash"
    LC_NUMERIC=C ros2 launch agx_arm_moveit demo.launch.py arm_type:=${ARM_TYPE:-piper} effector_type:=${EFFECTOR_TYPE:-agx_gripper}

  실물 로봇은 먼저 'sudo ./scripts/host-can-up.sh' 로 can0 을 올린 뒤 ./scripts/run-real.sh
  (docs/real-robot-checklist.md 필독 — 실기계 런치는 아직 네이티브 미검증).
EOF
