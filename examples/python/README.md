# Python MoveIt2 예제

Piper 팔을 파이썬으로 MoveIt2 제어하는 예제 모음입니다. 개요·배경은 메인 README 의
**"## Python 으로 MoveIt2 제어 (예제)"** 섹션을 참고하세요.

## 파일

| 파일 | API | 내용 |
|---|---|---|
| `ex01_pymoveit2_basic.py` | `pymoveit2` | 관절공간 목표 이동, 홈 복귀, 두 번째 MoveIt2 인스턴스로 그리퍼 열기/닫기, 속도/가속 스케일링 |
| `ex02_pymoveit2_cartesian_scene.py` | `pymoveit2` | IK POSE 목표 + 직선 Cartesian PATH, 플래닝 씬 충돌 박스 추가/우회/제거 |
| `ex03_moveit_py_official.py` | `moveit_py` | 공식 바인딩. SRDF 이름 상태 계획, 관절/포즈 목표, 충돌물체 회피, 다중 파이프라인 |
| `ex03_moveit_py.launch.py` | — | ex03 을 in-process `move_group`(+mock ros2_control, 컨트롤러)으로 띄우는 런치 |

## 사전 준비

```bash
sudo apt install ros-jazzy-pymoveit2 ros-jazzy-moveit-py
```

## 실행

### pymoveit2 (ex01, ex02) — `run-mock.sh` 가 먼저 떠 있어야 함

`pymoveit2` 는 이미 떠 있는 `move_group` 의 클라이언트입니다.

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

### moveit_py (ex03) — 단독 실행 (`run-mock.sh` 와 같이 띄우지 말 것)

`moveit_py` 는 자체 `move_group` 을 in-process 로 띄웁니다. 실행 대상은 스크립트가 아니라 런치 파일입니다.

```bash
source /opt/ros/jazzy/setup.bash
source ~/piper-rwh/ros2_ws/install/setup.bash
LC_NUMERIC=C ros2 launch ~/piper-rwh/examples/python/ex03_moveit_py.launch.py
```

기본으로 RViz 가 떠서 팔 움직임을 볼 수 있습니다(모션은 RViz 가 뜬 뒤 ~6초부터). 헤드리스면 `use_rviz:=false`. `예제 완료` 후에도 런치는 계속 떠 있으니 **Ctrl-C** 로 종료.
