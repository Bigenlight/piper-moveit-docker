# direct 프로파일 안전성 — 기존 로컬 ROS2 시스템과 충돌하지 않는 근거

`direct` 프로파일(호스트에서 직접 ROS 제어 + 데스크탑)을 켜고 `scripts/host-ros-env.sh` 를
source 했을 때, **호스트에서 이미 돌고 있던 다른 ROS 2 로봇 시스템이 깨지거나 연결이 끊기지 않는가?**

**결론: 깨지지 않는다.** 환경변수는 셸 한정이고, DDS 도메인으로 격리되며, 방화벽 변경은 순수 추가(좁은 ACCEPT)다.
아래는 추측이 아니라 실제 호스트에서 측정한 근거다.

---

## 무엇이 바뀌나 (변경 표면 전체)

| 변경 | 범위 | 영속성 |
|---|---|---|
| `host-ros-env.sh` 의 export (ROS_DOMAIN_ID=42, RMW, FASTDDS_BUILTIN_TRANSPORTS=UDPv4, ROS_STATIC_PEERS, DISCOVERY_RANGE) | **source 한 셸 1개만** | 그 셸 종료 시 사라짐 |
| `/opt/ros/jazzy` source | source 한 셸 1개만 | 일시적 |
| `ros2 daemon stop` (헬퍼 안) | 도메인 42 데몬만 (export 이후 실행) | CLI 캐시, 자동 재생성 |
| 방화벽 규칙 `172.28.0.0/16 → 172.28.0.1 INPUT ACCEPT` | **호스트 전역** | 재부팅 시 사라짐(영구화는 옵션) |
| 도커 bridge `piper-direct-net` (172.28.0.0/16) | 호스트 라우팅 테이블 | `compose down` 시 사라짐 |

전역으로 영속되는 변경은 **방화벽 ACCEPT 규칙 하나뿐**이고, 그것도 "허용만 추가"라 기존 연결을 막을 수 없다.

---

## 근거 ① 환경변수는 그 셸에서만 유효 — 전역 오염 없음

`source` 는 실행한 터미널 하나의 환경만 바꾼다. `.bashrc` 등을 영구 수정하지 않는다.
기존에 돌던 ROS 프로세스는 자기 셸/launch 환경(도메인 0)을 그대로 유지하며, 헬퍼를 source 해도 영향받지 않는다.

측정 (기존 호스트 ROS 작업이 멀쩡히 가동 중):
```
PID 3124242 theo_lab 02:50:15 robot_state_publisher ... -r joint_states:=control/joint_states   # 도메인 0
PID 3124651 theo_lab 02:50:05 robot_state_publisher ...                                           # 도메인 0
PID 3305488 theo_lab          ros2-daemon --ros-domain-id 0 --rmw-implementation rmw_fastrtps_cpp
```
→ 사용자의 기존 시스템은 도메인 0. 새 터미널에서 헬퍼를 source 해도 이 프로세스들의 환경은 안 바뀐다.

---

## 근거 ② DDS 도메인 격리 — 라이브로 증명됨 (가장 결정적)

기존 작업 = **도메인 0**, `direct` = **도메인 42**. DDS 는 도메인 ID 로 UDP 포트가 갈린다
(포트 = 7400 + 250 × 도메인). 0 과 42 는 물리적으로 다른 포트 → 서로 보이지도 간섭하지도 못한다.

측정 (두 도메인을 동시에 조회):
```
도메인 0 (기존 시스템이 보는 그래프):
   /robot_state_publisher              ← 컨테이너 노드(/move_group 등) 안 보임 ✅ 누수 없음

도메인 42 (direct 컨테이너 그래프):
   /controller_manager
   /move_group
   /moveit_simple_controller_manager
   /robot_state_publisher
```
→ 도메인 0 에서 컨테이너 노드가 전혀 안 보인다. 두 그래프가 동시에 멀쩡히 떠 있는 것 자체가 비간섭의 산 증거다.

> ⚠️ 단, 사용자가 **본인 작업을 일부러 `ROS_DOMAIN_ID=42` 로 돌리면** 컨테이너와 그래프를 공유하게 된다.
> 기본값(0)이나 42 이외의 도메인을 쓰면 무관하다.

---

## 근거 ③ 방화벽 변경은 순수 추가 + 좁음 + 비충돌

측정 (호스트 INPUT 체인):
```
-P INPUT DROP                                          # 기존 UFW 정책 (그대로, 안 건드림)
-A INPUT -s 172.28.0.0/16 -d 172.28.0.1/32 -j ACCEPT   # 우리가 넣은 규칙 — 이것 하나
```
- **ACCEPT 는 허용만 추가** → 기존 연결을 차단하는 것이 원천적으로 불가능. (위험한 건 DROP/REJECT 추가인데 그건 안 함.)
- 대상이 `172.28.0.0/16 → 172.28.0.1`, 즉 **도커 bridge 서브넷 → 게이트웨이**로 한정.

서브넷 비충돌 측정 (호스트 인터페이스):
```
127.0.0.1/8        lo
166.104.146.30/24  enp6s0          # 실로봇/LAN — 별개 대역
172.17.0.1/16      docker0         # 기본 도커 — 별개 대역
100.72.72.5/32     tailscale0      # 별개 대역
172.28.0.1/16      br-xxxx         # piper-direct-net (우리 것) — 유일한 172.28 사용처
```
→ 172.28.0.0/16 은 우리 bridge 전용. 기존 LAN/도커/VPN 대역과 하나도 안 겹쳐, 새 라우트가 기존 경로를 가릴 일이 없다.

---

## 주의할 점 (시스템 파괴가 아니라 운영 위생)

1. **헬퍼는 새 터미널에서 source.** 기존 ROS 작업 중인 셸에 덮어쓰면 그 셸만 도메인 42/UDPv4 로 바뀌어 혼동을 준다(그 셸 한정).
2. **본인 작업에 도메인 42 를 쓰지 말 것.** 기본 0 이나 다른 도메인을 쓰면 컨테이너와 완전히 분리된다.
3. **방화벽 영구화(옵션).** 재부팅 후에도 유지하려면 한 번만: `sudo ufw allow from 172.28.0.0/16 to 172.28.0.1` (이것도 ACCEPT 라 기존을 막지 않음). 안 하면 재부팅 시 규칙이 사라지고 헬퍼가 다음 source 때 다시 넣는다.
4. **LAN 미세 chatter.** 헬퍼 셸(도메인 42)은 `ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET` 이라 LAN 에도 도메인 42 discovery 패킷을 약간 흘린다. 같은 LAN 의 다른 머신이 도메인 42 를 쓰지 않는 한 전부 무시되어 실해는 없다. 완전 무소음을 원하면 static-peer 만 쓰고 range 를 OFF 로 좁힐 수 있다(현재는 검증된 설정 유지).

---

## 직접 확인하는 법

기존 로봇 시스템을 켜둔 채 `direct` 를 띄우고, 두 도메인을 비교하면 서로 안 섞이는 걸 눈으로 볼 수 있다:
```bash
# 기존 시스템(도메인 0)이 보는 그래프 — 컨테이너 노드가 없어야 정상
ROS_DOMAIN_ID=0 ros2 node list

# direct 컨테이너(도메인 42) 그래프 — 헬퍼 환경에서
source scripts/host-ros-env.sh && ros2 node list
```
