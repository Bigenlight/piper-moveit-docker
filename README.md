# Piper MoveIt — ROS 2 Jazzy (로컬/네이티브)

AgileX **Piper** 로봇팔(그리퍼 포함)을 **호스트에 깔린 ROS 2 Jazzy에서 바로** MoveIt2로 띄우고 조작하는 리포입니다.

Docker/noVNC 시절을 접고, 이제는 Ubuntu 24.04 + ROS 2 Jazzy가 깔린 이 머신에 스택을 **직접 설치**해서 돌립니다. mock(로봇 없이)이든 real(실물 CAN)이든, 런치 한 방이면 **RViz MotionPlanning 창이 로컬 데스크탑에 그냥 뜹니다.** 브라우저도, 포트도, 컨테이너도 없습니다.

> **한 줄 가치**: 호스트 Jazzy에서 `ros2 launch` 한 줄이면 mock 데모가 바로 돌아갑니다. (실물 로봇만 CAN 어댑터 추가로 필요)

---

## 개요

- **환경**: Ubuntu 24.04 + ROS 2 Jazzy (`/opt/ros/jazzy`) — 이 머신에 직접 설치. 별도 이미지/컨테이너 없음.
- **통합**: MoveIt2 + ros2_control + AgileX `agx_arm_ros` (Piper용 MoveIt config / 컨트롤러 / 런치)
- **두 가지 실행**: `mock`(가짜 하드웨어, 로봇 없이 데모) / `real`(실물 CAN 로봇)
- **재현성**: 외부 소스는 `versions.env` 의 두 SHA 로 못박음 → `AGX_ARM_ROS_SHA`(서브모듈), `PYAGXARM_SHA`(pip 설치) (자세한 건 아래 "재현성 / 핀" 참고)

보기만 되는 게 아니라 **진짜 조작이 됩니다.** RViz는 로컬 네이티브 창이라 마커 드래그, Plan & Execute, 그리퍼 열고 닫기 다 됩니다.

> GPU는 신경 안 써도 됩니다 — 호스트에 NVIDIA 드라이버가 깔려 있으면 네이티브 RViz가 알아서 GPU 가속을 씁니다.

---

## 설치

갓 clone 했으면 아래 스크립트 한 방이면 됩니다:

```bash
./scripts/setup-native.sh
```

이 스크립트가 apt 패키지 설치 → 서브모듈 초기화 → pyAgxArm(+python-can) 설치 → colcon 빌드까지 다 해줍니다. 재실행해도 안전(멱등)합니다.

### 수동으로 하려면 (스크립트가 하는 일 그대로)

전제: 이 머신에 **ROS 2 Jazzy(`/opt/ros/jazzy`) 가 이미 설치돼 있어야** 합니다. 없으면 [ROS 2 Jazzy 설치](https://docs.ros.org/en/jazzy/Installation.html) 부터.

**1) ROS/시스템 패키지 (apt)**

```bash
sudo apt install -y --no-install-recommends \
  ros-jazzy-moveit ros-jazzy-ros2-control ros-jazzy-ros2-controllers \
  ros-jazzy-controller-manager ros-jazzy-joint-trajectory-controller \
  ros-jazzy-joint-state-broadcaster ros-jazzy-gripper-controllers \
  ros-jazzy-parallel-gripper-controller ros-jazzy-robot-state-publisher \
  ros-jazzy-xacro ros-jazzy-topic-tools can-utils ethtool python3-pip git
```

(`rviz2` / `colcon` / `rosdep` 등은 `ros-jazzy-desktop` 에 이미 들어 있으면 생략됩니다.)

**2) 서브모듈 (핀된 agx_arm_ros)**

```bash
git submodule update --init --recursive   # agx_arm_ros + (중첩) agx_arm_urdf
```

**3) pyAgxArm (Python 드라이버) + python-can**

```bash
# pyAgxArm 을 versions.env 의 PYAGXARM_SHA 로 checkout 한 뒤 설치
pip3 install --user --break-system-packages .
pip3 install --user --break-system-packages python-can
```

> ⚠️ **Ubuntu 24.04 는 PEP 668 externally-managed 환경**입니다. `pip3 install --user` **만 쓰면 거부당합니다.**
> 반드시 `--user` **와** `--break-system-packages` 를 **둘 다** 붙이세요. 이렇게 하면 `~/.local` 에만 설치돼서
> sudo 없이, 시스템 오염 없이 들어갑니다. (setup-native.sh 가 알아서 이 조합으로 설치합니다.)

**4) colcon 빌드**

```bash
cd ros2_ws
source /opt/ros/jazzy/setup.bash
colcon build --symlink-install
```

`agx_arm_ctrl` / `agx_arm_description` / `agx_arm_moveit` / `agx_arm_msgs` 4개 패키지가 빌드됩니다.

---

## 빠른 시작 (mock, 로봇 없이)

로봇 하드웨어 하나 없이 그냥 데모 보고 싶을 때. 이게 일상 경로입니다.

```bash
source /opt/ros/jazzy/setup.bash
source ~/piper-rwh/ros2_ws/install/setup.bash
LC_NUMERIC=C ros2 launch agx_arm_moveit demo.launch.py arm_type:=piper effector_type:=agx_gripper
```

(래퍼 `./scripts/run-mock.sh` 로도 동일하게 띄울 수 있습니다.)

잠시 후 **RViz(MoveIt MotionPlanning)** 창이 로컬 데스크탑에 뜹니다.

> **~30초 기다리세요.** move_group + 컨트롤러(`arm_controller` / `gripper_controller` / `joint_state_broadcaster`)가 완전히 active 되고 RViz에 로봇이 제대로 뜰 때까지 대략 30초 걸립니다. **터미널 로그에 `You can start planning now!` 가 보이면 준비 끝.**

그냥 보기만 하는 게 아닙니다. **마우스로 마커 드래그하고, Plan & Execute 누르고, 그리퍼 열고 닫는 거 전부** 그 RViz 창에서 됩니다.

---

## 그리퍼 / 팔 조작

RViz의 **MotionPlanning** 패널에서:

1. **Planning Group** 을 `arm`(팔) 또는 `gripper`(그리퍼)로 바꿉니다.
2. 팔: 인터랙티브 마커(end-effector)를 드래그해서 목표 자세를 잡거나, **Planning** 탭의 **Goal State** 에서 named state를 고릅니다.
3. 그리퍼: named state `gripper_open` / `gripper_close` 를 고르거나 그리퍼 마커를 움직입니다.
4. **Plan & Execute** 클릭 → 실행됩니다. (mock에선 가짜 하드웨어가 받아주고, real에선 실제 팔이 움직임)

CLI로 직접 확인하고 싶으면 새 터미널에서 (예시):

```bash
# 새 터미널 — 소싱 두 줄 먼저
source /opt/ros/jazzy/setup.bash
source ~/piper-rwh/ros2_ws/install/setup.bash

# 현재 관절 피드백 보기 — 주의: /joint_states 가 아니라 리맵된 토픽을 봐야 함
#   mock : /control/joint_states      (가짜 하드웨어 상태)
#   real : /feedback/joint_states     (실물 팔이 CAN 으로 올리는 실제 자세)
ros2 topic echo /control/joint_states      # mock
# ros2 topic echo /feedback/joint_states   # real

# 컨트롤러 상태 확인
ros2 control list_controllers
```

> **함정**: 관절 피드백 토픽은 `/joint_states` 가 아니라 리맵됩니다 — **mock 은 `/control/joint_states`**,
> **real 은 `/feedback/joint_states`**(실물 피드백). echo 가 안 나온다고 당황하지 마세요.

---

## 개발

소스 고치고 다시 돌리는 흐름은 단순합니다:

```bash
cd ros2_ws
source /opt/ros/jazzy/setup.bash
colcon build --symlink-install
source install/setup.bash
LC_NUMERIC=C ros2 launch agx_arm_moveit demo.launch.py arm_type:=piper effector_type:=agx_gripper
```

`--symlink-install` 이라 파이썬/설정 파일은 재빌드 없이 반영되는 경우가 많지만, C++ 이나 새 파일을 건드렸으면 `colcon build --symlink-install` 로 다시 빌드하세요. RViz는 똑같이 로컬 창으로 뜹니다.

> `ros2_ws/src/agx_arm_ros` 는 **핀된 서브모듈이라 읽기 전용**입니다. 여기 코드를 직접 고치지 마세요.

---

## 실물 로봇 (리눅스 + CAN)

> **리눅스 + USB-CAN 어댑터가 필요합니다.** CAN은 리눅스 커널 기능(SocketCAN)이라, **로봇이 꽂힌 그 머신에서 직접** 돌려야 합니다.
>
> 📋 **첫 구동 전 반드시**: 전원/마운트/펌웨어·URDF 호환/첫 모션 안전절차까지 **[docs/real-robot-checklist.md](docs/real-robot-checklist.md)** 를 먼저 읽으세요. 아래는 요약입니다.

**띄우기 전 체크 (요약):**
- [ ] USB-CAN 꽂고 `ip link show type can` 으로 can0 확인
- [ ] **전원 24 V·≥10 A**, 베이스 **M5 4볼트 고정**, 작업반경 **626 mm 비우기**, 페이로드 ≤1.5 kg
- [ ] **물리 E-stop 없음** → 24 V 커넥터에 손 올릴 사람 지정
- [ ] **티치(teach) 모드 OFF** — 세션 중 티치 버튼 누르지 말 것 (누르면 제어가 막힘, 아래 ⚠️)
- [ ] 그리퍼 없으면 런치 인자를 `effector_type:=none` 으로
- [ ] 펌웨어 **≥ S-V1.6-3**(URDF DH 일치), 가능하면 ≥ S-V1.8-5 (기동 로그에서 확인)

> ⚠️ **티치 모드는 반드시 꺼진 상태로 시작.** 팔이 teach 모드면 드라이버가 로그에 `Agx_arm is in teach mode, cannot control` 을
> 찍고 **MoveIt/CAN 제어를 전부 거부**합니다. **세션 중엔 티치 버튼을 아예 누르지 마세요.** 실수로 눌렀으면 그 세션 제어가 막히니
> 빠져나와야 합니다 — `ros2 service call /exit_teach_mode std_srvs/srv/Empty "{}"` (piper 계열만) 또는 **팔 전원 재인가(재시작)**.
> 🚨 단 펌웨어 **S-V1.7-3 은 teach 를 빠져나올 때 토크가 풀려 팔이 떨어집니다** — 반드시 팔을 받친 상태에서 (S-V1.8-5+ 는 seamless).
> **한 세션은 수동(teach) 또는 MoveIt(CAN) 중 하나만.** 자세한 건 [piper-sdk-guide §6-1](docs/piper-sdk-guide.md).

**구동:**

> ⚠️ **미검증 / 예상**: 아래 real 런치 커맨드는 서브모듈 `agx_arm_ctrl` 런치파일의 인자를 확인해 구성한 것으로,
> **현재 이 호스트에 CAN 어댑터가 없어 네이티브로는 아직 검증되지 않았습니다.** 인자명/동작은 실제 하드웨어에서 확인하세요.

```bash
# 0) 어댑터 인식 확인 (팔 전원 켠 상태)
lsusb | grep -iE "1d50|606f"          # gs_usb USB-CAN 어댑터 보이는지
ip link show type can                  # can0 가 (DOWN 이라도) 잡혀 있어야 정상

# 1) 호스트 CAN 올리기 + 확인 (sudo 필요)
sudo ./scripts/host-can-up.sh        # gs_usb 로드 + can0 up @1Mbps (down-first, txqueuelen 포함)
candump can0                          # (팔 켠 상태) 프레임 흐르는지 확인
ip -details -statistics link show can0 # state UP + ERROR-ACTIVE(정상). BUS-OFF 면 케이블/종단/전원 확인

# 2) 띄우기
source /opt/ros/jazzy/setup.bash
source ~/piper-rwh/ros2_ws/install/setup.bash
LC_NUMERIC=C ros2 launch agx_arm_ctrl start_single_agx_arm_moveit.launch.py \
  can_port:=can0 arm_type:=piper effector_type:=agx_gripper
```

(래퍼 `./scripts/run-real.sh` 는 can0 가 UP 인지 확인한 뒤 위 런치를 대신 실행합니다. sudo host-can-up 은 안전상 자동으로 돌리지 않으니 먼저 직접 실행하세요.)

> **참고**: `auto_enable` 기본값이 `true` 라 bring-up 즉시 팔에 힘이 들어갑니다(STIFF). 처음엔 `speed_percent:=20` 정도로 낮춰서 시작하는 걸 권합니다.

**기동(~30초) 후 첫 모션 — MoveIt Plan & Execute 만:**
- `ros2 control list_controllers` active 확인 + `ros2 topic echo --once /feedback/joint_states` 값이 실제 자세와 일치하는지 확인 (안 맞으면 멈추기)
- RViz 에서 velocity/accel scaling **0.05–0.10**, Goal `home`, **Plan → 궤적 확인 → Execute** (전원에 손 올린 채)
- ❌ 첫 구동에 컨트롤러 직접 `action send_goal` / MIT / `fast_mode` 금지 (충돌·리밋 검사 우회)

**비상정지 (모션 중 이상하면):**
```bash
# 소프트 정지 = 현재 자세 유지 (물리 E-stop 이 없으니 이게 소프트 스톱). 안 되면 24V 커넥터를 뽑는다.
ros2 service call /emergency_stop std_srvs/srv/Empty "{}"
```

**안전 종료 순서 (⚠️ 이 순서 지킬 것 — 잘못하면 팔이 떨어진다):**
```bash
# 1) RViz 로 팔을 낮고 안정된 rest 자세로 이동 (home=곧게 선 자세라 rest 아님!)
# 2) 그 rest 자세에서만 모터 disable (disable 시 팔에 힘 풀림 → 받쳐진 자세에서만)
ros2 service call /enable_agx_arm std_srvs/srv/SetBool "{data: false}"
# 3) 런치 터미널에서 Ctrl-C (안 죽으면: pkill -f start_single_agx_arm_moveit)
# 4) CAN 내리기
sudo ip link set can0 down
```
> 모션 중이거나 rest 아닌 위치에서 launch 를 kill / 모터 disable 하지 마세요 — 팔이 최저에너지 자세로 떨어져 테이블·자기 자신을 칩니다.

기본 CAN 인터페이스/보율은 `versions.env` 의 `CAN_IFACE=can0` / `CAN_BITRATE=1000000`(1Mbps 고정). 더 자세한 절차·안전·트러블슈팅은 **[docs/real-robot-checklist.md](docs/real-robot-checklist.md)** 참고.

> 🖥️ **노트북 CPU 가 플래닝에 버거우면**: 로봇은 노트북, 연산은 다른 PC 로 나누는 분산(ROS 2 multi-machine) 구성도 가능. 단 **저수준 제어는 로봇 붙은 머신에 로컬 유지 + 유선 LAN 필수**. [체크리스트 §7](docs/real-robot-checklist.md) 참고.

---

## 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| 접속했는데 로봇이 안 뜸 / 컨트롤러 inactive | **~30초 기다리세요.** move_group + 컨트롤러 완전 active까지 시간이 걸립니다. 터미널 로그에 `You can start planning now!` 뜨면 끝. |
| `/joint_states` echo 가 빈값 | 피드백 토픽이 리맵됩니다 — **mock 은 `/control/joint_states`**, **real 은 `/feedback/joint_states`**. 그쪽을 보세요. |
| 숫자 파싱 / locale 관련 에러 (move_group "expects a double") | 런치 앞에 `LC_NUMERIC=C` 를 붙이세요(위 커맨드에 이미 포함). C 로케일은 소수점 `.` 을 쓰므로 파싱 문제를 회피합니다. 이 호스트엔 `en_US.UTF-8` 이 생성돼 있지 않아 일부러 C 로케일을 씁니다(locale-gen 불필요). 셸에 `export LC_NUMERIC=C` 로 걸어둬도 됩니다. |
| (real) `firmware version` / `enable status True` 가 안 뜸 | CAN 미연결/포트 불일치. 호스트가 **두 개 이상 CAN 인터페이스**를 가질 수 있으니(예: can0=Piper 1Mbps, can1=타 장치 500kbps), `candump can0` 로 프레임이 흐르고 `ip -details link show can0` 이 `bitrate 1000000` 인지로 Piper 쪽을 확인. |

---

## 재현성 / 핀

외부 소스를 `versions.env` 에 두 SHA 로 못박아 둡니다:

| 변수 | 값 | 의미 |
|---|---|---|
| `AGX_ARM_ROS_SHA` | `e649916179f19b29fdcfbe00b23a54afbc1c024d` | AgileX `agx_arm_ros` commit (서브모듈 gitlink 과 일치) |
| `PYAGXARM_SHA` | `a226840db0c3d5c5dc7f3ec78d6cef1a6800f9e6` | `pyAgxArm` commit (pip 설치가 checkout 하는 SHA) |

> **이게 핵심**: AgileX `agx_arm_ros` / `pyAgxArm` 레포는 릴리스 태그가 없습니다. 그래서 브랜치가 아니라 **commit SHA로 핀**합니다. 안 그러면 다음 사람이 셋업할 때 브랜치가 움직여서 깨질 수 있습니다. `agx_arm_ros` 는 서브모듈 gitlink 로도 고정돼 있고, `versions.env` 의 값은 사람이 읽는 기록 겸 대조용입니다.

(Docker 시절의 `BASE_IMAGE` digest 핀은 이제 없습니다 — 베이스 이미지 자체가 없으니까요. 필요하면 `legacy/docker/versions.env` 에 원본이 남아 있습니다.)

---

## Python 으로 MoveIt2 제어 (예제)

Jazzy 에서 MoveIt2 를 파이썬으로 구동하는 길은 두 가지입니다.

- **`moveit_py`** (공식 바인딩): 자체 `move_group` 을 **in-process 로 직접 띄웁니다**. 자기만의 런치 파일이 필요하고, `run-mock.sh`(demo.launch.py)와 **동시에 띄우면 안 됩니다**(move_group 이 둘이 되어 충돌). SRDF 이름 상태(`home` 등) 계획이 강점.
- **`pymoveit2`** (커뮤니티): **이미 떠 있는 `move_group` 의 클라이언트**일 뿐입니다. 이 리포에서는 `run-mock.sh` 로 올린 `move_group` 에 붙어서 동작하므로 가볍게 시작하기 좋습니다.

먼저 두 패키지를 설치하세요(아직 미설치):

```bash
sudo apt install ros-jazzy-pymoveit2 ros-jazzy-moveit-py
```

| 예제 | API | 보여주는 것 |
|---|---|---|
| [examples/python/ex01_pymoveit2_basic.py](examples/python/ex01_pymoveit2_basic.py) | `pymoveit2` | 관절공간 목표 이동(`move_to_configuration`), 홈 복귀, 두 번째 MoveIt2 인스턴스(`group_name="gripper"`)로 그리퍼 열기/닫기, 속도/가속 스케일링, MultiThreadedExecutor 데몬 스레드 스핀 |
| [examples/python/ex02_pymoveit2_cartesian_scene.py](examples/python/ex02_pymoveit2_cartesian_scene.py) | `pymoveit2` | IK 기반 POSE 목표(`cartesian=False`), 직선 CARTESIAN PATH(`cartesian=True`), 플래닝 씬 충돌 박스 추가/우회/제거, 속도/가속 스케일링 |
| [examples/python/ex03_moveit_py_official.py](examples/python/ex03_moveit_py_official.py) + [ex03_moveit_py.launch.py](examples/python/ex03_moveit_py.launch.py) | `moveit_py` | SRDF 이름 상태 계획(`set_goal_state(configuration_name="home")`), 관절/포즈 목표, planning scene 충돌물체 회피, MultiPipelinePlanRequestParameters 다중 파이프라인 + 단일 폴백 |

### pymoveit2 예제 (ex01, ex02)

`move_group` 이 먼저 떠 있어야 합니다. **터미널 1** 에서 `run-mock.sh` 를 띄우고 로그에 `You can start planning now!` 가 나올 때까지 기다리세요.

```bash
# 터미널 1
./scripts/run-mock.sh        # "You can start planning now!" 대기
```

그 다음 **터미널 2** 에서:

```bash
# 터미널 2
source /opt/ros/jazzy/setup.bash
source ~/piper-rwh/ros2_ws/install/setup.bash
python3 examples/python/ex01_pymoveit2_basic.py            # 또는 ex02_pymoveit2_cartesian_scene.py
```

> 그리퍼는 GripperCommand 가 아니라 JointTrajectoryController 라, `GripperInterface` 대신 `group_name="gripper"` 인 두 번째 MoveIt2 인스턴스로 제어합니다.

### moveit_py 예제 (ex03)

**단독 실행합니다 — `run-mock.sh` 와 같이 띄우지 마세요.** 자체 런치가 in-process `move_group` + mock ros2_control + 컨트롤러 스포너를 모두 올립니다. 실행 대상은 스크립트가 아니라 **런치 파일**입니다.

```bash
source /opt/ros/jazzy/setup.bash
source ~/piper-rwh/ros2_ws/install/setup.bash
LC_NUMERIC=C ros2 launch ~/piper-rwh/examples/python/ex03_moveit_py.launch.py
```

> 기본으로 **RViz 가 떠서 팔이 움직이는 걸 볼 수 있습니다**(RViz 가 먼저 뜨도록 모션은 시작 ~6초 뒤부터). 헤드리스로 돌리려면 `use_rviz:=false`. 스크립트가 `예제 완료`를 찍어도 런치는 계속 떠 있으니 확인 후 **Ctrl-C** 로 종료하세요.

---

## 참고자료

- **Piper 레퍼런스 모음** → **[docs/references.md](docs/references.md)** — 공식 문서/SDK/ROS2 드라이버/시뮬/텔레옵·RL 링크를 검증해서 정리 (구 스택 `piper_*` vs 신 스택 `agx_arm_*` 구분 포함).
- **Piper SDK / 장비 가이드** → **[docs/piper-sdk-guide.md](docs/piper-sdk-guide.md)**

---

## Docker 레거시

이 리포는 원래 noVNC 기반 Docker 구성이었습니다. 그 시절 파일(Dockerfile / docker-compose / noVNC / direct 프로파일 / CI 등)은 **[legacy/docker/](legacy/docker/)** 에 기록용으로 동결해 뒀습니다. 지금은 유지보수하지 않으며, 네이티브 셋업에는 필요 없습니다 — 궁금하면 참고만 하세요.

---

## 출처 / 라이선스

- **로봇 통합**: AgileX [`agx_arm_ros`](https://github.com/agilexrobotics/agx_arm_ros) + `pyAgxArm`
- **모션 플래닝**: [MoveIt2](https://moveit.ai/)
- **Docker 레거시**: 옛 baseimage 는 [Tiryoh/docker-ros2-desktop-vnc](https://github.com/Tiryoh/docker-ros2-desktop-vnc) (Apache-2.0) — 상세는 `legacy/docker/` 참고.

이 리포 자체의 라이선스는 추후 정합니다.
