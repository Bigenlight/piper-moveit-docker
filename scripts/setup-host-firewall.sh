#!/usr/bin/env bash
# === Piper MoveIt Docker — direct 프로파일용 호스트 방화벽 설정 ===
# 왜 필요한가 (BUILD/TEST 가 찾은 진짜 원인):
#   호스트 INPUT 체인이 'policy DROP' (UFW 활성). 호스트→컨테이너는 FORWARD 체인(도커가 허용)이라 되는데,
#   컨테이너→호스트(게이트웨이 172.28.0.1) 패킷은 INPUT 체인에 걸려 DROP 됨.
#   Fast DDS discovery 는 양방향이라 컨테이너의 응답/announce 가 호스트에 안 닿아 `ros2 node list` 가 빈 채로 나옴.
#   → 이 bridge 서브넷(172.28.0.0/16)에서 호스트로 들어오는 트래픽을 INPUT 에서 ACCEPT 시켜야 함.
#
# 멱등(idempotent): 이미 규칙이 있으면 아무것도 안 함. 여러 번 돌려도 안전.
# 인터페이스 이름이 아니라 SUBNET 기준이라 'compose down/up' 으로 bridge 가 새로 생겨도 그대로 유효.
#
# 사용법 (둘 중 하나):
#   sudo bash scripts/setup-host-firewall.sh          # 호스트에 passwordless sudo 있을 때 (권장)
#   bash scripts/setup-host-firewall.sh                # sudo 없으면 piper-moveit:jazzy 이미지로 iptables 조작(자동 fallback)
#
# 영구화(재부팅 후에도 유지)는 호스트 정책에 맡김. 가장 깔끔한 영구화:
#   sudo ufw route allow ...  는 INPUT 이 아니라 FORWARD 라 여기선 안 맞음. 대신:
#   sudo ufw allow from 172.28.0.0/16 to 172.28.0.1   # UFW 로 영구 등록(재부팅 생존). 한 번만.
# 이 스크립트는 즉시 적용(런타임)용. 재부팅 생존을 원하면 위 ufw 한 줄을 추가로 실행할 것.

set -euo pipefail

SUBNET="${PIPER_DIRECT_SUBNET:-172.28.0.0/16}"
GW="${PIPER_DIRECT_GW:-172.28.0.1}"
IMG="${IMAGE:-piper-moveit:jazzy}"

# iptables 를 어떻게 실행할지 결정: 호스트에 직접 권한이 있으면 그걸 쓰고, 아니면 privileged 컨테이너로.
ipt() {
    if [ "$(id -u)" = "0" ] && command -v iptables >/dev/null 2>&1; then
        iptables "$@"
    elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && command -v iptables >/dev/null 2>&1; then
        sudo iptables "$@"
    else
        # fallback: 호스트 netns 에 붙는 privileged 컨테이너로 호스트 iptables 조작.
        docker run --rm --net=host --privileged --entrypoint iptables "$IMG" "$@"
    fi
}

# 멱등 체크 후 삽입.
if ipt -C INPUT -s "$SUBNET" -d "$GW" -j ACCEPT 2>/dev/null; then
    echo "[setup-host-firewall] 규칙 이미 존재: INPUT accept $SUBNET -> $GW (변경 없음)"
else
    ipt -I INPUT 1 -s "$SUBNET" -d "$GW" -j ACCEPT
    echo "[setup-host-firewall] 규칙 추가됨: INPUT accept $SUBNET -> $GW"
fi
