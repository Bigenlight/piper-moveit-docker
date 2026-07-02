#!/usr/bin/env bash
# === Piper MoveIt Docker — host 직접 ROS 제어용 환경 설정 (direct 프로파일) ===
# 사용법 (호스트 터미널에서, 반드시 `source` 로 — 실행이 아니라 현재 셸에 적용해야 함):
#   docker compose --profile direct up -d direct    # 컨테이너를 전용 bridge(고정 IP)로 띄우고
#   source scripts/host-ros-env.sh                   # 호스트 셸에 DDS 환경 적용
#   ros2 node list                                   # 호스트에서 컨테이너 ROS 그래프가 바로 보인다
#   ros2 action send_goal /arm_controller/follow_joint_trajectory ...   # 호스트에서 팔 제어
#   # 동시에 브라우저로 http://localhost:6080 → RViz 에서 같은 팔이 움직이는 걸 볼 수 있음
#
# direct 프로파일은 host-network 가 아니라 전용 bridge(172.28.0.0/16, 컨테이너 172.28.0.2)다.
# multicast 가 bridge 를 못 넘으므로 유니캐스트 static-peer 로 서로를 시드한다:
#   - 컨테이너 → ROS_STATIC_PEERS=172.28.0.1 (게이트웨이=호스트)
#   - 호스트   → ROS_STATIC_PEERS=172.28.0.2 (컨테이너 고정 IP, 아래에서 설정)
# cross-UID(호스트 vs 컨테이너 ubuntu) 라 SHM 데이터 경로가 깨짐 → UDPv4 강제.
# 도메인 42 로 호스트의 기존 ROS(도메인 0) 와 격리.
#
# 컨테이너 IP/도메인을 바꿨다면 source 전에 export 로 덮어쓸 수 있음:
#   PIPER_CONTAINER_IP=172.28.0.2 ROS_DOMAIN_ID=42 source scripts/host-ros-env.sh

PIPER_CONTAINER_IP="${PIPER_CONTAINER_IP:-172.28.0.2}"

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTDDS_BUILTIN_TRANSPORTS=UDPv4              # bridge 너머 discovery/데이터가 UDP 로 넘어가도록
export ROS_STATIC_PEERS="${PIPER_CONTAINER_IP}"      # 컨테이너를 유니캐스트 discovery peer 로 시드
export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET          # static-peer 가 서브넷 너머 붙도록
unset ROS_LOCALHOST_ONLY                             # Jazzy deprecated. 켜져 있으면 discovery 를 막을 수 있어 해제.

# 호스트 방화벽(UFW INPUT policy DROP) 때문에 컨테이너→호스트 discovery 응답이 막힌다.
# bridge 서브넷에서 호스트로 들어오는 트래픽을 INPUT 에서 ACCEPT 시켜야 ros2 node list 가 채워진다.
# (멱등: 이미 있으면 no-op. 자세한 원인은 scripts/setup-host-firewall.sh 주석 참조.)
_PIPER_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "${_PIPER_HELPER_DIR}/setup-host-firewall.sh" ]; then
    bash "${_PIPER_HELPER_DIR}/setup-host-firewall.sh" || \
        echo "[host-ros-env] WARN: 방화벽 규칙 설정 실패. 컨테이너→호스트 discovery 가 막혀 node list 가 빌 수 있음. scripts/setup-host-firewall.sh 를 sudo 로 수동 실행해보세요." >&2
fi

# 호스트 ROS 2 Jazzy 환경 로드 (호스트에 ros-jazzy-* 가 설치돼 있어야 함).
if [ -f /opt/ros/jazzy/setup.bash ]; then
    # shellcheck disable=SC1091
    source /opt/ros/jazzy/setup.bash
else
    echo "[host-ros-env] WARN: /opt/ros/jazzy/setup.bash 없음. 호스트에 ROS 2 Jazzy 가 설치돼 있어야 ros2 CLI 가 동작합니다." >&2
fi

# 이전 세션의 캐시가 phantom 노드를 보일 수 있으니 데몬 리셋(도메인/트랜스포트/peer 바뀌면 필수).
ros2 daemon stop >/dev/null 2>&1 || true

# bridge 너머 유니캐스트 discovery 는 즉시 안 채워질 수 있음(컨테이너/네트워크 갓 띄운 직후 ~20-30초 소요).
# node list 가 비면 실패가 아니라 "수렴 대기" 중. 이 함수로 /move_group 이 보일 때까지 기다릴 수 있음:
#   piper_wait_ready        # 최대 60초 폴링
piper_wait_ready() {
    local timeout="${1:-60}" i
    echo "[piper_wait_ready] 컨테이너 ROS 그래프 discovery 대기 (최대 ${timeout}s)..."
    for i in $(seq 1 "${timeout}"); do
        if ros2 node list 2>/dev/null | grep -q '/move_group'; then
            echo "[piper_wait_ready] OK (${i}s): /move_group 발견. 이제 ros2 명령을 쓰세요."
            return 0
        fi
        sleep 1
    done
    echo "[piper_wait_ready] WARN: ${timeout}s 내 미발견. 'docker compose --profile direct ps' 로 컨테이너 상태,"
    echo "                    'bash scripts/setup-host-firewall.sh' 로 방화벽 규칙을 확인하세요." >&2
    return 1
}

echo "[host-ros-env] ROS_DOMAIN_ID=${ROS_DOMAIN_ID} RMW=${RMW_IMPLEMENTATION} TRANSPORT=${FASTDDS_BUILTIN_TRANSPORTS} STATIC_PEERS=${ROS_STATIC_PEERS}"
echo "[host-ros-env] 준비됨. 컨테이너가 'docker compose --profile direct up -d direct' 로 떠 있어야 함."
echo "[host-ros-env] ⚠ discovery 가 ~20-30초 걸릴 수 있음 → node list 가 비면 'piper_wait_ready' 로 기다리세요."
