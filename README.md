# Piper MoveIt Docker

AgileX **Piper** 로봇팔(그리퍼 포함)을 **브라우저 안에서** MoveIt2로 띄우고 조작하는 리포입니다.

[Tiryoh noVNC ROS2 데스크탑](https://github.com/Tiryoh/docker-ros2-desktop-vnc) 베이스 위에 **MoveIt2** + AgileX **agx_arm_ros** 를 통합해서, mock(로봇 없이)이든 real(실물 CAN)이든 `http://localhost:6080` 한 번 열면 RViz MotionPlanning이 데스크탑에 떠 있습니다.

> **한 줄 가치**: 호스트 OS 안 따집니다. 윈도우든 맥이든 리눅스든 **Docker만 있으면** mock 데모가 바로 돌아갑니다. (실물 로봇만 리눅스+CAN 필요)

---

## 개요

- **베이스**: `ghcr.io/tiryoh/ros2-desktop-vnc:jazzy` — Ubuntu 24.04 + ROS 2 Jazzy + noVNC 데스크탑(포트 6080) 내장
- **통합**: MoveIt2 + ros2_control + AgileX `agx_arm_ros` (Piper용 MoveIt config / 컨트롤러 / 런치)
- **모드**: `mock`(가짜 하드웨어) / `direct`(호스트 ros2 직접제어+데스크탑) / `dev`(코드 마운트 셸) / `real`(실물 CAN) / `gpu`(NVIDIA 가속 mock)
- 모든 외부 소스는 SHA/digest로 핀됨 → **재현성 보장** (자세한 건 아래 "재현성 / 핀" 참고)

조작은 **보기만 되는 게 아니라 진짜 조작이 됩니다.** noVNC는 원격 데스크탑이라 마커 드래그, Plan & Execute, 그리퍼 열고 닫기 다 됩니다.

---

## 빠른 시작 (mock, 로봇 없이)

로봇 하드웨어 하나 없이 그냥 데모 보고 싶을 때. 이게 일상 경로입니다.

```bash
docker compose --profile mock up
# 또는 동일하게:
docker compose up mock
```

그다음 브라우저로:

```
http://localhost:6080
```

데스크탑이 뜨면 잠시 후 **RViz(MoveIt MotionPlanning)** 가 자동으로 올라옵니다.

> **~30초 기다리세요.** move_group + 컨트롤러(`arm_controller` / `gripper_controller` / `joint_state_broadcaster`)가 완전히 active 되고 RViz에 로봇이 제대로 뜰 때까지 대략 30초 걸립니다. 컨테이너 로그에 `You can start planning now!` 가 보이면 준비 끝.

그냥 보기만 하는 게 아닙니다. 원격 데스크탑이라서 **마우스로 마커 드래그하고, Plan & Execute 누르고, 그리퍼 열고 닫는 거 전부 브라우저 안에서 됩니다.**

---

## 그리퍼 / 팔 조작

RViz의 **MotionPlanning** 패널에서:

1. **Planning Group** 을 `arm`(팔) 또는 `gripper`(그리퍼)로 바꿉니다.
2. 팔: 인터랙티브 마커(end-effector)를 드래그해서 목표 자세를 잡거나, **Planning** 탭의 **Goal State** 에서 named state를 고릅니다.
3. 그리퍼: named state `gripper_open` / `gripper_close` 를 고르거나 그리퍼 마커를 움직입니다.
4. **Plan & Execute** 클릭 → 실행됩니다. (mock에선 가짜 하드웨어가 받아주고, real에선 실제 팔이 움직임)

CLI로 직접 던지고 싶으면 컨테이너 셸에서 (예시):

```bash
# 컨테이너 안에서
source /opt/ros/jazzy/setup.bash
source /ws/install/setup.bash

# 현재 관절 피드백 보기 — 주의: /joint_states 아니라 /control/joint_states 로 리맵됨
ros2 topic echo /control/joint_states

# 컨트롤러 상태 확인
ros2 control list_controllers
```

> **함정**: 관절 피드백 토픽은 `/joint_states`가 아니라 **`/control/joint_states`** 로 리맵되어 있습니다. echo가 안 나온다고 당황하지 마세요.

---

## 개발 (코드 마운트)

`./ros2_ws` 를 컨테이너 `/ws` 로 바인드 마운트해서, 호스트에서 코드 편집하면 바로 반영되는 모드입니다.

```bash
docker compose --profile dev up -d
docker compose exec dev bash
```

컨테이너 셸 안에서:

```bash
cd /ws
colcon build --symlink-install
source install/setup.bash
ros2 launch agx_arm_moveit demo.launch.py arm_type:=piper effector_type:=agx_gripper
```

호스트의 `./ros2_ws` 안 파일을 편집하면 컨테이너 `/ws` 에 **바로 반영**됩니다. (마운트가 이미지 내장 빌드를 덮어쓰므로, 안에서 직접 `colcon build` 하세요.) RViz는 똑같이 `http://localhost:6080` 에서 봅니다.

---

## 호스트에서 직접 ROS 제어 + 데스크탑 동시 (direct 프로파일)

mock 은 컨테이너 안에서만 ROS 가 돕니다(호스트 터미널 `ros2` 는 못 닿음). **호스트의 `ros2` CLI/스크립트로 컨테이너 로봇을 직접 제어하면서 동시에 RViz 데스크탑도 보고 싶을 때** `direct` 프로파일을 씁니다. (예: 호스트의 Python/RL 코드에서 팔을 굴리고, 움직임은 브라우저 RViz 로 확인)

작동 원리: host-network 가 아니라 **전용 bridge(고정 IP `172.28.0.2`)** 라 noVNC 데스크탑(6080)이 그대로 살아있고, 호스트↔컨테이너 ROS 는 **Fast DDS 유니캐스트 static-peer + UDPv4** 로 bridge 경계를 넘습니다. (멀티캐스트는 bridge 를 못 넘고, cross-UID 라 SHM 도 못 씀)

> **전제**: 호스트에 **ROS 2 Jazzy** 가 설치돼 있어야 호스트에서 `ros2` 를 쓸 수 있습니다 (`source /opt/ros/jazzy/setup.bash`). 윈도우/맥은 이 프로파일 대신 mock 을 쓰고 컨테이너 안에서 제어하세요.

**터미널 A — 컨테이너 띄우기:**

```bash
docker compose --profile direct up -d direct
# 브라우저 → http://localhost:6080  (RViz 데스크탑)
```

**터미널 B — 호스트에서 제어:**

```bash
source scripts/host-ros-env.sh     # DDS 환경(도메인 42 / UDPv4 / static-peer) 적용 + 방화벽 규칙 자동 등록(멱등)
piper_wait_ready                   # discovery 수렴 대기 (~20-30초 걸릴 수 있음). node list 가 비면 이걸로 기다리기
ros2 node list                     # → 컨테이너의 /move_group, /controller_manager ... 가 보임
ros2 action send_goal /arm_controller/follow_joint_trajectory control_msgs/action/FollowJointTrajectory \
  "{trajectory: {joint_names: [joint1,joint2,joint3,joint4,joint5,joint6], points: [{positions: [0.6,0.0,-0.3,0.0,0.0,0.0], time_from_start: {sec: 2, nanosec: 0}}]}}"
# → SUCCEEDED. 터미널 A 브라우저 RViz 에서 같은 팔이 동시에 움직이는 게 보임
```

> ⚠️ **방화벽**: 호스트 UFW 가 `INPUT policy DROP` 이면 컨테이너→호스트 discovery 응답이 막혀 `ros2 node list` 가 빕니다. `scripts/host-ros-env.sh` 가 `scripts/setup-host-firewall.sh` 를 자동 호출해 **`172.28.0.0/16 → 172.28.0.1` INPUT ACCEPT** 규칙(딱 이 bridge 서브넷만)을 멱등 등록합니다. sudo 없으면 privileged 컨테이너로 폴백. **재부팅 후에도 유지**하려면 한 번만: `sudo ufw allow from 172.28.0.0/16 to 172.28.0.1`.
>
> ⚠️ **discovery 지연**: 컨테이너/네트워크를 갓 띄운 직후엔 유니캐스트 discovery 가 즉시 안 채워질 수 있습니다(~20-30초). `node list` 가 비어도 실패가 아니라 수렴 대기 중 — `piper_wait_ready` 로 기다리세요.
>
> ⚠️ **보안**: noVNC 가 무인증(127.0.0.1 바인딩)으로 열리고 ROS 그래프가 bridge 에 노출됩니다. 신뢰된 랩 머신에서만 쓰세요. 컨트롤러에 직접 골을 쏘면 MoveIt 충돌검사를 건너뛰니, 실물에선 RViz Plan & Execute 를 권장합니다.

---

## 실물 로봇 (리눅스 + CAN)

> **리눅스 전용입니다.** 윈도우 / 맥에서는 실물 로봇을 못 돌립니다 — CAN은 리눅스 커널 기능(SocketCAN)이라 컨테이너가 호스트 커널의 CAN 인터페이스를 빌려야 하기 때문입니다. 윈도우/맥은 `mock` / `dev` 만 가능합니다.

1. 호스트에서 CAN 인터페이스를 올립니다 (sudo 필요):

   ```bash
   sudo ./scripts/host-can-up.sh
   ```

2. 팔에 전원을 넣습니다.

3. real 프로파일로 띄웁니다:

   ```bash
   docker compose --profile real up
   ```

real 서비스는 `network_mode: host` + `privileged: true` 로 돌아갑니다 (can0 접근 위해). **host 네트워크라서 compose 의 포트 매핑(6080:80)이 무시되고, noVNC 는 컨테이너 내부 포트 그대로 호스트의 80 번에 노출됩니다** → `http://localhost` (6080 아님, 그냥 80).

기본 CAN 인터페이스/보율은 `versions.env` 의 `CAN_IFACE=can0` / `CAN_BITRATE=1000000` 입니다.

> ⚠️ **보안 경고**: `real` 은 `privileged: true` + `network_mode: host` 라서 사실상 **호스트 root 권한과 동등**하고, noVNC 데스크탑은 **무인증으로 호스트 80 번에 그대로 열립니다** (LAN 에서 누구나 접속 → 팔을 움직일 수 있음). 신뢰할 수 있는 랩 머신 + 격리된 네트워크에서만 쓰고, 공용망에 노출하지 마세요. (mock/dev 는 compose 에서 `127.0.0.1` 로만 바인딩되어 안전.)

---

## GPU (옵션)

RViz 3D를 좀 더 부드럽게 돌리고 싶으면 NVIDIA GPU 가속 mock을 씁니다. 호스트에 **nvidia-container-toolkit** 이 설치돼 있어야 합니다.

```bash
docker compose --profile gpu up gpu
```

mock과 동일한데 NVIDIA GPU를 예약해서 붙입니다. RViz 회전/렌더링이 한결 부드러워집니다.

---

## 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| RViz / Qt 가 크래시 | 공유메모리 부족. compose에 `shm_size: "512m"` 이미 들어가 있음. 직접 `docker run` 할 땐 `--shm-size 512m` 꼭 붙이세요. |
| 접속했는데 로봇이 안 뜸 / 컨트롤러 inactive | **~30초 기다리세요.** move_group + 컨트롤러 완전 active까지 시간이 걸립니다. 로그에 `You can start planning now!` 뜨면 끝. |
| `/joint_states` echo 가 빈값 | 피드백 토픽이 **`/control/joint_states`** 로 리맵됨. 그쪽을 보세요. |
| 숫자 파싱 / locale 관련 에러 (move_group "expects a double") | `LC_NUMERIC=C` 로 설정됨 (컨테이너 env 기본값). C 로케일은 소수점 `.` 을 쓰므로 locale-gen 없이 파싱 문제 회피. en_US.UTF-8 은 베이스에 생성돼 있지 않아 일부러 안 씁니다. |
| `docker compose exec` 로 들어갔는데 `ros2 node list` 가 비어 보임 | ROS 프로세스는 유저 `ubuntu` 로 돌고 DDS 공유메모리가 유저별이라, 기본 root 셸에서는 그래프가 안 보입니다. **`docker compose exec -u ubuntu mock bash`** 로 들어가세요. |
| noVNC 3D 화면이 빠른 회전 때 끊김 | noVNC 특성상 빠른 시점 회전은 좀 버벅입니다. **조작 자체는 정상**이니 천천히 돌리면 됩니다. (부드럽게 원하면 GPU 프로파일) |
| (direct) 호스트 `ros2 node list` 가 빔 | ① discovery 수렴 대기(~20-30초) → `piper_wait_ready`. ② 호스트 UFW INPUT DROP → `bash scripts/setup-host-firewall.sh` (헬퍼가 자동 호출하지만 수동 확인 가능). ③ 도메인 확인: `echo $ROS_DOMAIN_ID` 가 42 여야 함(헬퍼 source 했는지). |
| (direct) `topic echo` 에 "A message was lost" | bridge 경유 UDPv4 유니캐스트의 일시적 알림. **데이터는 정상 도착**하니 무시해도 됩니다. |

---

## 재현성 / 핀

모든 외부 소스를 `versions.env` 에 못박아 둡니다. 수정 금지(읽기 전용)입니다.

| 변수 | 값 | 의미 |
|---|---|---|
| `BASE_IMAGE` | `ghcr.io/tiryoh/ros2-desktop-vnc:jazzy@sha256:0a5fc7…` | 베이스 데스크탑 이미지 (digest 핀) |
| `AGX_ARM_ROS_SHA` | `e649916179f19b29fdcfbe00b23a54afbc1c024d` | AgileX `agx_arm_ros` commit |
| `PYAGXARM_SHA` | `a226840db0c3d5c5dc7f3ec78d6cef1a6800f9e6` | `pyAgxArm` commit |

> **이게 핵심**: AgileX `agx_arm_ros` 레포는 릴리스 태그가 없습니다. 그래서 브랜치가 아니라 **commit SHA로 핀**합니다. 안 그러면 다음 사람이 빌드할 때 ros2 브랜치가 움직여서 깨질 수 있습니다.

베이스 이미지도 `@sha256:<digest>` 형태로 **digest 핀** 되어 있습니다 (`:jazzy` 태그는 시간 지나면 갱신되므로). 이 digest 는 multi-arch 인덱스라 amd64/arm64 둘 다 같은 베이스를 가리킵니다. 베이스를 새 버전으로 올리려면 `docker buildx imagetools inspect ghcr.io/tiryoh/ros2-desktop-vnc:jazzy` 로 새 digest 를 확인해 `versions.env` 를 갱신하세요.

---

## GHCR 사용 (빌드 없이 받기)

CI가 main에 머지될 때마다 이미지를 빌드해서 GHCR로 자동 push합니다. 직접 빌드 안 하고 그냥 받고 싶으면:

```bash
docker pull ghcr.io/Bigenlight/piper-moveit:jazzy
```

`Bigenlight` 는 `versions.env` 의 `OWNER` 값(GitHub 계정/org)입니다. pull 후엔 compose에서 그 이미지를 쓰도록:

```bash
IMAGE=ghcr.io/Bigenlight/piper-moveit:jazzy docker compose up mock
```

(로컬 빌드는 `OWNER` 무관 — 기본 태그 `piper-moveit:jazzy` 로 동작합니다.)

---

## 출처 / 라이선스

- **베이스**: [Tiryoh/docker-ros2-desktop-vnc](https://github.com/Tiryoh/docker-ros2-desktop-vnc) — Apache-2.0
- **로봇 통합**: AgileX [`agx_arm_ros`](https://github.com/agilexrobotics/agx_arm_ros) + `pyAgxArm`
- **모션 플래닝**: [MoveIt2](https://moveit.ai/)

이 리포 자체의 라이선스는 추후 정합니다.
