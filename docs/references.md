# AgileX Piper 레퍼런스 모음 (검증됨)

Piper 로봇팔 입문·구동·ROS2·시뮬·텔레옵에 유용한 링크를 한곳에 정리했습니다.
이 리포(`direct`/`mock` 프로파일)는 아래 **신 스택**(`agx_arm_ros` + `pyAgxArm`)을 SHA 핀해서 씁니다.

> ⚠️ **AgileX 레포 = 2세대 공존** (2026-06 확인): `piper_*`(구·Piper 전용) → `agx_arm_*` + `pyAgxArm`(신·전 기종 통합)으로 무게중심 이동 중.
> **Nero(2번째 팔, 2025-05 출시)가 방아쇠** ← 팔이 여러 기종이 되며 `piper_` 네이밍으로 못 버팀.
> 공식 go-forward 는 **신 스택**이지만, 문서·데모·서드파티 래퍼·커뮤니티 자료는 **아직 구 스택이 압도적**(별 14배 차, agx 는 릴리스 태그도 없음).
> → **24.04/Jazzy·멀티암이면 신 스택, 막혔을 때 트러블슈팅 자료는 구 스택 병행.**

---

## 🟢 공통 (공식)

| 자료 | 링크 | 용도 |
|---|---|---|
| 공식 제품 페이지 (스펙) | https://global.agilex.ai/products/piper | 페이로드 1.5kg, 리치 626mm, $1,999 |
| Quick Start 매뉴얼 PDF | https://static1.squarespace.com/static/5e76e0c52a318c0c1a850442/t/66fa9477f980111a86b42e8b/1727698043682/PiPER+quick+start+user+manual+EN(1).pdf | 배선·전원·LED·드래그티칭 (v1.0, 2024.09) |
| GitHub Org 전체 | https://github.com/agilexrobotics | 공식 레포 탐색 (팔만 `agx_arm_*` 통합) |
| 공식 Discord | https://discord.gg/wrKYTxwDBd | 사실상 메인 Q&A 채널 |
| 이메일 지원 / 펌웨어 요청 | support@agilex.ai | 펌웨어 셀프 업뎃 불가, 메일로 받아야 함 |

---

## 🟢 신 스택 — `agx_arm_*` / `pyAgxArm` (공식 go-forward · 전 기종 통합) ⭐ 이 리포가 쓰는 것

> Piper/X/H/L/Nero/Revo2 한 stack 으로. **24.04/Jazzy 는 사실상 이쪽이 답.**
> 단 어리고(2026 초 생성) 릴리스 태그·PyPI 없음 → Docker 등에선 **commit SHA 핀** 권장 (이 리포는 `versions.env` 에 핀).

| 자료 | 링크 | 비고 |
|---|---|---|
| **agx_arm_ros** (통합 ROS2 드라이버) | https://github.com/agilexrobotics/agx_arm_ros | `ros2` 브랜치, **Humble+Jazzy**, MoveIt2 포함, pyAgxArm 의존. `piper_ros` 후속 |
| **pyAgxArm** (통합 Python SDK) | https://github.com/agilexrobotics/pyAgxArm | Piper/X/H/L/Nero/Revo2. `piper_sdk` 후속. CAN 통신. PyPI·릴리스 아직 없음 |
| pyAgxArm API docs (Piper) | https://github.com/agilexrobotics/pyAgxArm/tree/master/docs/piper | 기종별 API 문서 |
| agx_arm_urdf (통합 URDF/Xacro+메시) | https://github.com/agilexrobotics/agx_arm_urdf | 공유 submodule, MIT |
| agx_arm_sim (통합 sim 툴킷) | https://github.com/agilexrobotics/agx_arm_sim | Isaac Sim + MoveIt2 + RViz2, 전 기종 |

---

## 🟢 구 스택 — `piper_*` (Piper 전용 · 자료 최다 · 실질 표준)

> 입문·트러블슈팅은 여기가 제일 빠름. 단 **유지보수 모드**(신규 기능 X)이고 **Jazzy 미지원**.

| 자료 | 링크 | 비고 |
|---|---|---|
| **piper_sdk** (Python SDK) ⭐ | https://github.com/agilexrobotics/piper_sdk | 자료 제일 풍부 = 실질 표준. CAN 스크립트·데모 다수. v0.6.1(2025.10) 이후 유지보수만 |
| 데모 스크립트 (V2) | https://github.com/agilexrobotics/piper_sdk/tree/master/piper_sdk/demo/V2 | enable/moveJ/moveL/gripper/reset/MIT 복붙용 |
| PyPI 패키지 | https://pypi.org/project/piper-sdk/ | `pip install piper-sdk` |
| CAN 프로토콜 / API 명세 | https://github.com/agilexrobotics/piper_sdk/blob/master/asserts/V2/INTERFACE_V2.MD | 메시지 ID표·관절한계·모드플래그 (`asserts` 오타는 원본 그대로) |
| **piper_ros** (ROS1/ROS2 드라이버) ⭐ | https://github.com/agilexrobotics/piper_ros | 브랜치 `noetic`/`foxy`/`humble`. **Jazzy 없음.** 별 최다 |
| piper_isaac_sim (Piper 전용 Isaac) | https://github.com/agilexrobotics/piper_isaac_sim | USD 씬, Ubuntu 24.04 |

---

## 🟡 공식 튜토리얼 (Hackster, AgileX 계정)

| 자료 | 링크 |
|---|---|
| 손-눈 캘리브레이션 (ROS2 Humble) | https://www.hackster.io/agilexrobotics/piper-hand-eye-calibration-0af35b |
| 운동학/자코비안 FK·IK | https://www.hackster.io/agilexrobotics/jacobian-magic-piper-arm-kinematics-unleashed-0d2f86 |
| URDF → Isaac Sim 임포트 | https://www.hackster.io/agilexrobotics/importing-piper-urdf-into-isaac-sim-17ecc5 |
| Genesis 시뮬 | https://www.hackster.io/agilexrobotics/piper-single-arm-simulation-and-control-on-genesis-8330f2 |

---

## 🟠 커뮤니티 (비공식, 유용)

| 자료 | 링크 | 비고 |
|---|---|---|
| **piper_control** (쉬운 래퍼) | https://github.com/Reimagine-Robotics/piper_control | enable/reset 시퀀싱 안정적 ← 공식 SDK 가 팔 먹통 만들 때 대안으로 인기 |
| MuJoCo 모델 | https://github.com/soulde/Piper_mujoco | ROS 불필요, 중력보상/IK |
| MarqRazz/piper_ros2 | https://github.com/MarqRazz/piper_ros2 | 깔끔한 ROS2-first, `piper_moveit_config` |
| 셋업 가이드 (SVRC) | https://www.roboticscenter.ai/hardware/agilex-piper | CAN→MoveIt→VR 텔레옵 정리 |

> ⚠️ 이름 충돌 주의: `Reimagine-Robotics/piper_ros`(커뮤니티)랑 `agilexrobotics/piper_ros`(공식)는 레포명이 같지만 **다른 프로젝트**임.

---

## 🤖 RL / 텔레옵 / VLA 연결점

| 자료 | 링크 | 비고 |
|---|---|---|
| LeRobot — SO-101 leader 매핑 PR | https://github.com/huggingface/lerobot/pull/1481 | 아직 main 머지 X (커뮤니티 PR) |
| LeRobot — 초기 PR (joystick/RealSense) | https://github.com/huggingface/lerobot/pull/645 | |
| lerobot_robot_piper (바로 쓰는 패키지) | https://github.com/AgRoboticsResearch/lerobot_robot_piper | teleop/record/ACT |
| openpi-agilex (VLA pi0/pi0.5 파인튜닝) | https://github.com/agilexrobotics/openpi-agilex | 듀얼암 ROS2, 공식 |
| GELLO 업스트림 SW | https://github.com/wuphilipp/gello_software | leader-follower 텔레옵 |

> 💡 GELLO식 텔레옵의 정공법 = **Piper master-slave CAN 모드**. Piper 두 대를 직접 연결하면
> `piper.MasterSlaveConfig(0xFC, 0, 0, 0)` 로 follower 를 slave 로 두고 leader 를 따라가게 할 수 있음(별도 leader 디바이스 불필요).
>
> ⚠️ "Sim2Real RL grasping" Hackster 글은 URL 에 piper 가 있지만 **실제 내용은 Nero 팔** 기준(PPO/Isaac Lab) ← Piper 에 그대로 적용 안 됨, 참고만.

---

*검증: 토픽별 web search 후 링크 40여 개를 실제 fetch 해서 확인 (2026-06). AgileX 레포 구조는 바뀔 수 있으니 막히면 GitHub Org 에서 최신 상태 확인.*
