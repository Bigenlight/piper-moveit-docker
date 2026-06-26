# Piper MoveIt Docker

AgileX **Piper** 로봇팔(그리퍼 포함)을 **브라우저 안에서** MoveIt2로 띄우고 조작하는 리포입니다.

[Tiryoh noVNC ROS2 데스크탑](https://github.com/Tiryoh/docker-ros2-desktop-vnc) 베이스 위에 **MoveIt2** + AgileX **agx_arm_ros** 를 통합해서, mock(로봇 없이)이든 real(실물 CAN)이든 `http://localhost:6080` 한 번 열면 RViz MotionPlanning이 데스크탑에 떠 있습니다.

> **한 줄 가치**: 호스트 OS 안 따집니다. 윈도우든 맥이든 리눅스든 **Docker만 있으면** mock 데모가 바로 돌아갑니다. (실물 로봇만 리눅스+CAN 필요)

---

## 개요

- **베이스**: `ghcr.io/tiryoh/ros2-desktop-vnc:jazzy` — Ubuntu 24.04 + ROS 2 Jazzy + noVNC 데스크탑(포트 6080) 내장
- **통합**: MoveIt2 + ros2_control + AgileX `agx_arm_ros` (Piper용 MoveIt config / 컨트롤러 / 런치)
- **모드**: `mock`(가짜 하드웨어) / `dev`(코드 마운트 셸) / `real`(실물 CAN) / `gpu`(NVIDIA 가속 mock)
- 모든 외부 소스는 SHA/digest로 핀됨 → **재현성 보장** (자세한 건 아래 "재현성 / 핀" 참고)

조작은 **보기만 되는 게 아니라 진짜 조작이 됩니다.** noVNC는 원격 데스크탑이라 마커 드래그, Plan & Execute, 그리퍼 열고 닫기 다 됩니다.

---

## 빠른 시작 (mock, 로봇 없이)

로봇 하드웨어 하나 없이 그냥 데모 보고 싶을 때. 이게 일상 경로입니다.

> ⚠️ **처음이면 이미지부터 빌드** (한 번만). compose 에는 `build:` 가 없어서 — `docker compose build` 는 *"No services to build"* —
> 이미지가 없으면 `docker compose up` 이 바로 실패합니다. 갓 clone 했으면 먼저:
> ```bash
> git submodule update --init --recursive   # agx_arm_ros + (중첩) agx_arm_urdf
> set -a; . ./versions.env; set +a
> docker build -t piper-moveit:jazzy \
>   --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg PYAGXARM_SHA="$PYAGXARM_SHA" .
> ```
> (자세히는 아래 [로컬 빌드](#로컬-빌드-처음-한-번). GHCR 이미지를 그냥 받으려면 [GHCR 사용](#ghcr-사용-빌드-없이-받기).)

빌드가 됐으면(또는 이미 이미지가 있으면):

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

# 현재 관절 피드백 보기 — 주의: /joint_states 가 아니라 리맵된 토픽을 봐야 함
#   mock : /control/joint_states      (가짜 하드웨어 상태)
#   real : /feedback/joint_states     (실물 팔이 CAN 으로 올리는 실제 자세) — 둘 다 존재
ros2 topic echo /control/joint_states      # mock
# ros2 topic echo /feedback/joint_states   # real

# 컨트롤러 상태 확인
ros2 control list_controllers
```

> **함정**: 관절 피드백 토픽은 `/joint_states` 가 아니라 리맵됩니다 — **mock 은 `/control/joint_states`**,
> **real 은 `/feedback/joint_states`**(실물 피드백). echo 가 안 나온다고 당황하지 마세요.

> **컨테이너 셸 진입**: ROS 노드는 유저 `ubuntu` 로 돌고 DDS 공유메모리가 유저별이라 **`-u ubuntu` 로 들어가야** 그래프가 보입니다.
> mock: `docker compose exec -u ubuntu mock bash` · real(host-net): `docker exec -u ubuntu piper-moveit-docker-real-1 bash` → 안에서 위 `source` 두 줄 먼저.

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

## 실물 로봇 (리눅스 + CAN)

> **리눅스 전용입니다.** 윈도우 / 맥에서는 실물 로봇을 못 돌립니다 — CAN은 리눅스 커널 기능(SocketCAN)이라 컨테이너가 호스트 커널의 CAN 인터페이스를 빌려야 하기 때문입니다. 윈도우/맥은 `mock` / `dev` 만 가능합니다.
>
> 📋 **첫 구동 전 반드시**: 전원/마운트/펌웨어·URDF 호환/첫 모션 안전절차까지 **[docs/real-robot-checklist.md](docs/real-robot-checklist.md)** 를 먼저 읽으세요. 아래는 요약입니다.

**호스트 OS 는 안 따집니다.** 22.04 노트북이든 24.04 든 컨테이너 안은 Jazzy 로 자기완결이라 상관없음. 호스트에서 필요한 건 ① 커널 SocketCAN/gs_usb(22.04·24.04 다 내장) ② Docker ③ USB-CAN 어댑터 ④ amd64 CPU(`uname -m`=x86_64, 이미지가 amd64 전용) 뿐. **로봇이 꽂힌 그 머신에서 `real` 을 돌려야 함**(SocketCAN 은 로컬 커널 기능 → 원격 불가).

**띄우기 전 체크 (요약):**
- [ ] `uname -m` = `x86_64`, Docker + compose v2 설치, 이미지 pull(또는 build)
- [ ] USB-CAN 꽂고 `ip link show type can` 으로 can0 확인
- [ ] **전원 24 V·≥10 A**, 베이스 **M5 4볼트 고정**, 작업반경 **626 mm 비우기**, 페이로드 ≤1.5 kg
- [ ] **물리 E-stop 없음** → 24 V 커넥터에 손 올릴 사람 지정
- [ ] 그리퍼 없으면 `EFFECTOR_TYPE=none` (compose `real` 블록에 줄이 없으니 추가하거나 `EFFECTOR_TYPE=none docker compose --profile real up`)
- [ ] 펌웨어 **≥ S-V1.6-3**(URDF DH 일치), 가능하면 ≥ S-V1.8-5 (기동 로그에서 확인)

**구동:**
```bash
# 0) 이미지 (처음 한 번) — compose 엔 build 섹션이 없으니 docker build 로. 자세히는 아래 "로컬 빌드".
git submodule update --init --recursive
set -a; . ./versions.env; set +a
docker build -t piper-moveit:jazzy --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg PYAGXARM_SHA="$PYAGXARM_SHA" .

# 1) 호스트 CAN 올리기 + 확인
sudo ./scripts/host-can-up.sh        # gs_usb 로드 + can0 up @1Mbps (down-first, txqueuelen 포함)
candump can0                          # (팔 켠 상태) 프레임 흐르는지 확인

# 2) 띄우기  (real = host network → 데스크탑은 http://localhost:6080)
docker compose --profile real up
```

> **real 도 noVNC 는 `http://localhost:6080`** (mock 과 동일 포트). real 은 host-network 라, 호스트가 자체
> 데스크탑(`:1`)을 쓰면 공유 netns 에서 X 디스플레이가 충돌하고 ubuntu 권한으론 포트 80 을 못 연다.
> 그래서 컨테이너가 기동 시 `desktop-realfix.sh` 로 VNC 를 `:2`, noVNC 를 `6080` 으로 자동 재배치한다
> (다른 프로파일은 영향 없음). 헤드리스 호스트라도 6080 으로 통일된다.

**기동(~30초) 후 첫 모션 — MoveIt Plan & Execute 만:**
- `ros2 control list_controllers` active 확인 + `ros2 topic echo --once /feedback/joint_states` 값이 실제 자세와 일치하는지 확인 (안 맞으면 멈추기)
- RViz 에서 velocity/accel scaling **0.05–0.10**, Goal `home`, **Plan → 궤적 확인 → Execute** (전원에 손 올린 채)
- ❌ 첫 구동에 컨트롤러 직접 `action send_goal` / MIT / `fast_mode` 금지 (충돌·리밋 검사 우회)

기본 CAN 인터페이스/보율은 `versions.env` 의 `CAN_IFACE=can0` / `CAN_BITRATE=1000000`(1Mbps 고정).

> ⚠️ **보안 경고**: `real` 은 `privileged: true` + `network_mode: host` 라서 사실상 **호스트 root 권한과 동등**하고, noVNC 데스크탑은 **무인증으로 호스트 6080 번에 그대로 열립니다** (LAN 에서 누구나 접속 → 팔을 움직일 수 있음). 신뢰할 수 있는 랩 머신 + 격리된 네트워크에서만 쓰고, 공용망에 노출하지 마세요. (mock/dev 는 compose 에서 `127.0.0.1` 로만 바인딩되어 안전.)
>
> 🖥️ **노트북 CPU 가 플래닝에 버거우면**: 로봇은 노트북, 연산은 24.04 PC 로 나누는 분산(ROS2 multi-machine) 구성도 가능. 단 **저수준 제어는 노트북 로컬 유지 + 유선 LAN 필수**. [체크리스트 §7](docs/real-robot-checklist.md) 참고.

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
| (real) noVNC 가 `localhost:80` 에서 안 열림 | **real 데스크탑은 `http://localhost:6080`** 입니다(80 아님). host-network 라 ubuntu 권한으로 80(<1024)을 못 열어 `desktop-realfix.sh` 가 noVNC 를 6080 으로 재배치합니다. |
| (real) 접속했는데 화면이 검음 / "갑자기 연결 끊김" | host-network 가 호스트의 X 디스플레이 `:1` 과 충돌 → 컨테이너 VNC 가 `:2` 로 재배치됩니다. 보통 자동 복구되지만, 끊기면 **브라우저 새로고침**. 그래도 안 되면 `docker exec piper-moveit-docker-real-1 supervisorctl status` 로 `vnc` 가 RUNNING 인지 확인(FATAL 이면 `docker exec piper-moveit-docker-real-1 supervisorctl restart vnc`). 화면잠금(MATE)은 desktop-realfix 가 꺼 둡니다. |
| (real) `firmware version` / `enable status True` 가 안 뜸 | CAN 미연결/포트 불일치. 호스트가 **두 개 이상 CAN 인터페이스**를 가질 수 있으니(예: can0=Piper 1Mbps, can1=타 장치 500kbps), `candump can0` 로 프레임이 흐르고 `ip -details link show can0` 이 `bitrate 1000000` 인지로 Piper 쪽을 확인. |

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

## 로컬 빌드 (처음 한 번)

`docker compose up` 은 이미지가 이미 있다고 가정합니다. 리포를 갓 clone 했으면 먼저 빌드하세요.
**compose 에는 `build:` 섹션이 없어 `docker compose build` 는 아무것도 안 합니다** — `docker build` 를 직접 씁니다:

```bash
git submodule update --init --recursive      # agx_arm_ros + (중첩) agx_arm_urdf. 안 하면 colcon 빌드 실패
set -a; . ./versions.env; set +a              # BASE_IMAGE / PYAGXARM_SHA 핀 값 로드
docker build -t piper-moveit:jazzy \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg PYAGXARM_SHA="$PYAGXARM_SHA" .  # AGX_ARM_ROS_SHA 는 서브모듈로 고정(빌드인자 아님)
```

빌드가 끝나면 `docker compose up mock` (또는 `--profile real up`) 으로 띄웁니다. (CI 빌드 이미지를 그냥 받으려면 아래 GHCR 참고.)

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

## 참고자료

- **Piper 레퍼런스 모음** → **[docs/references.md](docs/references.md)** — 공식 문서/SDK/ROS2 드라이버/시뮬/텔레옵·RL 링크를 검증해서 정리 (구 스택 `piper_*` vs 신 스택 `agx_arm_*` 구분 포함).

---

## 출처 / 라이선스

- **베이스**: [Tiryoh/docker-ros2-desktop-vnc](https://github.com/Tiryoh/docker-ros2-desktop-vnc) — Apache-2.0
- **로봇 통합**: AgileX [`agx_arm_ros`](https://github.com/agilexrobotics/agx_arm_ros) + `pyAgxArm`
- **모션 플래닝**: [MoveIt2](https://moveit.ai/)

이 리포 자체의 라이선스는 추후 정합니다.
