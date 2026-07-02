# SPEC — Piper MoveIt (네이티브 저작 계약)

이 파일은 여러 에이전트가 **일관되게** 네이티브 문서/스크립트를 만들기 위한 단일 계약이다. 값은 루트 `versions.env` 에서 가져온다. (구 Docker 시절 저작 계약은 `legacy/docker/SPEC.md` 에 그대로 보관돼 있음.)

## 목표
호스트에 직접 깔린 ROS 2 Jazzy(`/opt/ros/jazzy`) 위에서 Piper MoveIt2(그리퍼 포함) 를 **mock 데모** 로 바로 띄우고, 실물 팔(CAN)도 같은 워크스페이스로 돌린다. 컨테이너/noVNC/브라우저 없음 — RViz 는 로컬 X 데스크탑(:1)에 그냥 창으로 뜬다.

## 검증된 apt 세트 (이번 세션 실측 — 이 목록 그대로)
```
ros-jazzy-moveit ros-jazzy-ros2-control ros-jazzy-ros2-controllers \
ros-jazzy-controller-manager ros-jazzy-joint-trajectory-controller \
ros-jazzy-joint-state-broadcaster ros-jazzy-gripper-controllers \
ros-jazzy-parallel-gripper-controller ros-jazzy-robot-state-publisher \
ros-jazzy-xacro ros-jazzy-topic-tools can-utils ethtool python3-pip git
```
(rviz2/robot-state-publisher/colcon/rosdep 은 `ros-jazzy-desktop` 로 이미 있음, scipy/numpy 도 기본 존재.)

## 런치 커맨드
공통 소싱 2줄:
```
source /opt/ros/jazzy/setup.bash
source ~/piper-rwh/ros2_ws/install/setup.bash
```
- **mock (검증됨, 매일 쓰는 경로):**
  `LC_NUMERIC=C ros2 launch agx_arm_moveit demo.launch.py arm_type:=piper effector_type:=agx_gripper`
- **real (미검증 / 예상 — CAN 어댑터 미연결, docker 패리티 + 서브모듈 런치파일 대조로만 확인):**
  먼저 호스트에서 `sudo ./scripts/host-can-up.sh` (can0 @1Mbps),
  그 다음 `LC_NUMERIC=C ros2 launch agx_arm_ctrl start_single_agx_arm_moveit.launch.py can_port:=can0 arm_type:=piper effector_type:=agx_gripper`
  (auto_enable 기본 true → 브링업 즉시 팔이 STIFF. 첫 동작은 speed_percent 를 ~20 으로 낮춰서.)

## gotcha 3종 (반드시 보존)
1. **피드백 토픽 리맵**: 관절 상태는 `/joint_states` 가 아니다. mock = `/control/joint_states`, real = `/feedback/joint_states`(실물 실제 자세). RViz/echo 는 이걸 봐야 함.
2. **`LC_NUMERIC=C`**: C 로케일이 소수점을 '.' 로 써서 move_group 의 "expects a double" 회피. 컨테이너 ENV 가 없으니 커맨드 앞에 붙이거나 셸에서 export. (en_US.UTF-8 은 이 호스트에 미생성 — C 는 locale-gen 불필요.)
3. **~30초 대기**: move_group + 컨트롤러가 전부 active 되기까지 ~30초. 로그에 **"You can start planning now!"** 뜨면 준비 완료.

## mock 하드웨어
mock 은 `mock_components/GenericSystem` (Jazzy `hardware_interface` 내장) 을 쓴다. 실제 CAN/pyAgxArm 없이 컨트롤러 스택 전체가 뜬다.

## 재현성 핀 2종 (루트 versions.env)
| 핀 | 값 | 검증법 |
|---|---|---|
| `AGX_ARM_ROS_SHA` | `e649916179f19b29fdcfbe00b23a54afbc1c024d` | `git -C ros2_ws/src/agx_arm_ros rev-parse HEAD` 결과와 대조 (서브모듈 gitlink 이 진짜 핀, 이 값은 사람이 읽는 기록. `.gitmodules` 는 branch=ros2 로 floating) |
| `PYAGXARM_SHA` | `a226840db0c3d5c5dc7f3ec78d6cef1a6800f9e6` | pip 로 설치한 pyAgxArm 이 checkout 한 SHA |

## env 의미 (루트 versions.env)
| 변수 | 기본 | 의미 |
|---|---|---|
| `ARM_TYPE` | `piper` | 팔 종류 (piper/piper_x/h/l/nero) |
| `EFFECTOR_TYPE` | `agx_gripper` | 그리퍼 on(`agx_gripper`) / off(`none`) — 런치 인자로 전달 |
| `CAN_IFACE` | `can0` | real CAN 인터페이스 |
| `CAN_BITRATE` | `1000000` | CAN 보율 (고정) |

- **`MODE` 는 폐기**: docker entrypoint 의 mock/real/dev 디스패처용이었음. 네이티브는 런치 커맨드를 직접 골라 쓰므로 더 이상 존재하지 않는다. (도커 좌표 OWNER/IMAGE_*/BASE_IMAGE/NOVNC_PORT/DDS 블록도 루트본에서 제거 — 필요하면 `legacy/docker/versions.env` 참조.)

## pip 설치 규칙 (중요)
pyAgxArm 과 python-can 은 **`pip3 install --user --break-system-packages`** 로 깐다. Ubuntu 24.04 는 PEP668 externally-managed 라 `--user` 만으로는 거부되고, **두 플래그를 반드시 같이** 줘야 `~/.local` 에 깔린다(sudo 없음, 시스템 오염 없음). 구 Docker 시절의 "루트로 bare `--break-system-packages` 시스템 설치" 는 **이관 금지** — 네이티브 문서에 그렇게 쓰면 틀림.

## scripts/host-can-up.sh 계약
호스트에서 sudo 로 실행. `modprobe gs_usb`(실패해도 진행) → `ip link set ${CAN_IFACE:-can0} up type can bitrate ${CAN_BITRATE:-1000000}` → 상태 출력 + candump 힌트. 네이티브 real 경로의 필수 선행 단계라 루트 `scripts/` 에 유지(legacy 로 옮기지 말 것).

## 성공 기준
1. `colcon build --symlink-install` 성공 (agx_arm_ctrl / agx_arm_description / agx_arm_moveit / agx_arm_msgs 4패키지 통과).
2. mock 런치 후: `/move_group` 노드 살아있음, `ros2 control list_controllers` 에서 `joint_state_broadcaster` / `arm_controller`(joint_trajectory_controller) / `gripper_controller` 전부 **active**.
3. 로그에 **"You can start planning now!"**, RViz2 가 로컬 창으로 뜸.

## 금지 조항
`ros2_ws/src/agx_arm_ros/**` 는 핀된 서브모듈이다 — **절대 수정 금지**(읽기만). `legacy/**` 는 동결 아카이브라 손대지 않는다.
