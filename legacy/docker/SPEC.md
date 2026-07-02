# SPEC — Piper MoveIt Docker (저작 계약)

이 파일은 여러 에이전트가 **일관되게** 파일을 만들기 위한 단일 계약이다. 모든 파일은 이 SPEC을 따른다. 값은 `versions.env`에서 가져온다.

## 목표
누구나(윈도우/맥/리눅스) Docker만 있으면 **브라우저로 Piper MoveIt2(그리퍼 포함) mock 데모를 바로** 띄우고 조작. 실물은 리눅스+CAN. 의존성 문제 최소, 재현성 보장.

## 검증된 사실 (이미 실험으로 확인됨 — 이걸 그대로 반영)
- 베이스 `ghcr.io/tiryoh/ros2-desktop-vnc:jazzy` = Ubuntu24.04 + ROS2 Jazzy + noVNC 데스크탑(포트 6080) 이미 포함. ROS는 `/opt/ros/jazzy`.
- 필요한 apt 패키지셋(검증됨): `ros-jazzy-moveit ros-jazzy-ros2-control ros-jazzy-ros2-controllers ros-jazzy-controller-manager ros-jazzy-joint-trajectory-controller ros-jazzy-joint-state-broadcaster ros-jazzy-gripper-controllers ros-jazzy-parallel-gripper-controller ros-jazzy-robot-state-publisher ros-jazzy-xacro ros-jazzy-topic-tools can-utils ethtool`
- agx_arm_ros 빌드 후 mock 데모: `ros2 launch agx_arm_moveit demo.launch.py arm_type:=piper effector_type:=agx_gripper`
- 실물: `ros2 launch agx_arm_ctrl start_single_agx_arm_moveit.launch.py can_port:=can0 arm_type:=piper effector_type:=agx_gripper` (pyAgxArm 필요)
- **함정**: 관절 피드백 토픽은 `/joint_states` 아니라 `/control/joint_states`로 리맵됨. `LC_NUMERIC=en_US.UTF-8` 필요. move_group+컨트롤러 완전 active까지 ~30초.
- 24.04 PEP668: pip는 `--break-system-packages`. (컨테이너 안이라 시스템 설치 OK)
- mock hardware = `mock_components/GenericSystem` (Jazzy의 hardware_interface에 내장).

## 리포 구조 (이미 생성됨)
```
piper-moveit-docker/
├── Dockerfile                 [A1]
├── docker-compose.yml         [A2]
├── entrypoint.sh              [A2]
├── scripts/host-can-up.sh     [A3]
├── .github/workflows/build.yml[A3]
├── .gitignore                 [A3]
├── README.md                  [A4]
├── versions.env               (생성됨, 수정 금지 — 읽기만)
├── SPEC.md                    (이 파일)
└── ros2_ws/src/agx_arm_ros/   (submodule, 핀됨 — 건드리지 말 것)
```

## 이미지 좌표 / 핀 (versions.env)
- 로컬 태그: `piper-moveit:jazzy`  /  GHCR: `ghcr.io/${OWNER}/piper-moveit:jazzy`
- BASE_IMAGE=`ghcr.io/tiryoh/ros2-desktop-vnc:jazzy`
- AGX_ARM_ROS_SHA=`e649916179f19b29fdcfbe00b23a54afbc1c024d`
- PYAGXARM_SHA=`a226840db0c3d5c5dc7f3ec78d6cef1a6800f9e6`

## env 변수 계약 (이름·기본값 고정 — 전 파일 동일하게)
| 변수 | 기본 | 의미 |
|---|---|---|
| `MODE` | `mock` | `mock`(가짜HW) / `real`(CAN) / `dev`(셸) |
| `ARM_TYPE` | `piper` | piper/piper_x/h/l/nero |
| `EFFECTOR_TYPE` | `agx_gripper` | 그리퍼 on(`agx_gripper`)/off(`none`) |
| `CAN_IFACE` | `can0` | real CAN 인터페이스 |
| `CAN_BITRATE` | `1000000` | CAN 보율(고정) |
| `LC_NUMERIC` | `en_US.UTF-8` | locale 함정 회피 |

## 컨테이너 경로 계약
- 오버레이 워크스페이스: `/ws` (이미지에 agx_arm_ros 빌드 내장)
- dev 프로파일: 호스트 `./ros2_ws` → 컨테이너 `/ws` 마운트(내장 빌드 덮어씀, 안에서 colcon build)
- entrypoint: `/entrypoint.sh`

## Dockerfile 계약 [A1]
- `ARG BASE_IMAGE` → `FROM ${BASE_IMAGE}`
- apt로 위 "검증된 패키지셋" 설치 (`--no-install-recommends`, 끝에 apt 캐시 정리)
- `ARG PYAGXARM_SHA`: pyAgxArm clone→checkout SHA→`pip3 install --break-system-packages .` + `python-can scipy numpy`
- `COPY ros2_ws/src /ws/src` 후 `. /opt/ros/jazzy/setup.sh && colcon build --symlink-install` (at `/ws`)
- `COPY entrypoint.sh /entrypoint.sh` (+ 실행권한)
- `ENV` 기본값(ARM_TYPE/EFFECTOR_TYPE/LC_NUMERIC/MODE)
- `ENTRYPOINT ["/entrypoint.sh"]`, `CMD ["mock"]`
- 베이스의 noVNC(포트 6080) 기동을 깨지 말 것 — 우리 entrypoint는 ROS만 띄우고, noVNC 데스크탑은 베이스 메커니즘 유지(베이스 Dockerfile 확인해서 supervisord/起動 방식과 공존하도록. 데스크탑 세션에서 RViz가 뜨도록 DISPLAY 사용).

## entrypoint.sh 계약 [A2]
- 첫 인자 또는 `$MODE`로 분기: `mock` / `real` / `dev`(=bash)
- 항상: `source /opt/ros/jazzy/setup.bash`; `/ws/install`이 있으면 `source /ws/install/setup.bash`; `export LC_NUMERIC=en_US.UTF-8`
- `mock`: `ros2 launch agx_arm_moveit demo.launch.py arm_type:=${ARM_TYPE} effector_type:=${EFFECTOR_TYPE}`
- `real`: CAN_IFACE up 시도(권한 있으면 `ip link set ${CAN_IFACE} up type can bitrate ${CAN_BITRATE}`, 이미 up이면 통과), 그 후 `ros2 launch agx_arm_ctrl start_single_agx_arm_moveit.launch.py can_port:=${CAN_IFACE} arm_type:=${ARM_TYPE} effector_type:=${EFFECTOR_TYPE}`
- `dev`: 환경 source 후 `exec bash` (사용자가 직접 colcon build/launch)
- noVNC 데스크탑이 떠 있는 베이스와 공존해야 함 → entrypoint가 베이스 init을 막지 않게 설계(베이스의 기존 CMD/supervisor가 noVNC를 띄우는 구조면, 우리 런치는 그 데스크탑 세션 안에서 백그라운드로 돌리고 로그를 stdout으로). **A1/A2는 베이스 Dockerfile(github Tiryoh)을 실제로 확인해서 noVNC 기동을 안 깨는 방식을 택할 것.**

## docker-compose.yml 계약 [A2]
- `env_file: versions.env`
- 공통 x-앵커로 image/shm_size(`512m`)/ports(`${NOVNC_PORT}:6080`) 재사용
- 서비스(프로파일):
  - `mock`: 마운트 없음, `MODE=mock`, 포트 6080. (기본)
  - `real`: `network_mode: host`, `privileged: true`(can0 위해), `MODE=real`, `/dev` 접근. (리눅스 전용)
  - `dev`: `./ros2_ws:/ws` 마운트, `command: ["dev"]`, 포트 6080.
  - `gpu`: mock과 동일 + `deploy.resources.reservations.devices`(nvidia) 또는 `gpus: all` 주석/문서. (옵션)
- `IMAGE`는 `${OWNER}` 미정 시 로컬 `piper-moveit:jazzy` 기본으로 동작하게. `image: ${IMAGE:-piper-moveit:jazzy}`

## CI .github/workflows/build.yml 계약 [A3]
- 트리거: push to main, tags `v*`, workflow_dispatch, (옵션)주간 schedule
- buildx로 빌드, `ghcr.io/${{ github.repository_owner }}/piper-moveit` 로 push
- `GITHUB_TOKEN` + `permissions: packages: write` 사용(별도 secret 불필요)
- build-args로 BASE_IMAGE/AGX_ARM_ROS_SHA/PYAGXARM_SHA 전달(versions.env 값). 태그: `jazzy`, `sha-<short>`
- v1은 amd64. (arm64는 주석으로 확장 포인트)

## scripts/host-can-up.sh 계약 [A3]
- 호스트에서 실행(sudo). `modprobe gs_usb` (실패해도 진행), `ip link set ${CAN_IFACE:-can0} up type can bitrate ${CAN_BITRATE:-1000000}`, 상태 출력, `candump` 힌트. (udev 규칙은 주석으로 안내)

## README.md 계약 [A4]
- 한국어, 구어체. 섹션: 개요 / 빠른시작(mock, 브라우저 localhost:6080) / dev(코드 마운트) / real(리눅스+CAN) / GPU옵션 / 트러블슈팅(shm-size, 30초 대기, /control/joint_states, LC_NUMERIC) / 재현성(핀·versions.env) / 라이선스/출처(Tiryoh Apache-2.0, AgileX).
- "보기만 아니라 조작도 됨(원격 데스크탑)" 명시. 윈도우=mock OK, 실물=리눅스.

## 빌드/테스트 기준 (성공 정의)
1. `docker build` 성공 (콜콘 빌드 4패키지 통과).
2. `docker compose up mock` → `localhost:6080` 접속됨, 컨테이너 안에서 `/move_group` 노드 + `arm_controller`/`gripper_controller`/`joint_state_broadcaster` active, `mock_components/GenericSystem` active, 로그 "You can start planning now!".
3. 재현성: 모든 외부 소스가 SHA/digest로 핀.
