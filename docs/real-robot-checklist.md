# Piper MoveIt 실물 로봇 체크리스트

실제 Piper 팔을 연결하고 이 리포의 네이티브 ROS 2 Jazzy 셋업으로 구동하는 전체 절차.
첫 전원·첫 모션에서 **하드웨어 안 깨먹고 안전하게** 돌리는 게 목표.

> 호스트에서 실제로 중요한 건 ① 커널 SocketCAN/gs_usb ② ROS 2 Jazzy + 이 리포 워크스페이스 빌드 ③ USB-CAN 어댑터 ④ 드라이버 띄우기 전에 호스트에서 can0 up — 이 네 가지.
> ROS 2 Jazzy 설치와 워크스페이스 빌드는 루트 [README](../README.md) 의 설치 섹션 참고.

---

## 0. 아키텍처 — 어디서 뭘 돌리나

> **SocketCAN(can0)은 로컬 커널 기능**이라 네트워크 너머로 못 쓴다. **USB-CAN 어댑터가 꽂힌 그 머신에서 드라이버(저수준 제어)를 돌려야 한다.** 다른 PC 가 이 머신의 can0 을 원격으로 잡는 건 불가능.

- **A안 (기본·권장)**: 어댑터 꽂힌 머신 한 대에서 전부 돌린다. 드라이버 + MoveIt + RViz 다 로컬. → 이 문서가 다루는 경로.
- **B안 (분산, 선택)**: 이 머신은 CAN 드라이버만, 무거운 연산(MoveIt 플래닝/RL)은 다른 PC 에서 LAN 너머 ROS 2 로. 로컬이 플래닝에 버거울 때만. 끝의 [§7](#7-선택-분산-실행-b안) 참고. **저수준 제어 루프는 반드시 어댑터 머신 로컬 유지**(WiFi 금지).

---

## 1. 호스트 사전 준비

ROS 2 Jazzy + MoveIt/ros2_control 스택 설치, 서브모듈 init, pyAgxArm(`--user --break-system-packages`) 설치, `colcon build --symlink-install` 까지는 루트 [README](../README.md) 의 네이티브 설치 절차를 그대로 따르면 된다. 버전 핀(`AGX_ARM_ROS_SHA`, `PYAGXARM_SHA`)은 서브모듈 체크아웃 + pip 설치 SHA 로 이미 고정돼 있으니 여기서 따로 로드할 것 없음.

이 문서는 그 위에서 **실물 팔을 붙이는 부분**만 다룬다.

### CPU 아키텍처 확인 (amd64 전용)
```bash
uname -m            # x86_64 여야 함. aarch64(ARM) 노트북이면 pyAgxArm/휠 호환 별도 확인 필요.
```

---

## 2. CAN 어댑터 — 인식 & 활성화 (호스트에서)

Piper 어댑터는 **gs_usb(candleLight 계열) 네이티브 SocketCAN** 장치(slcan 시리얼 아님). Jazzy 커널에 `gs_usb` 내장 → 꽂으면 udev 가 자동 로드.

```bash
# 1) 꽂고 인식 확인
lsusb | grep -iE "1d50|606f|CAN"      # 어댑터 보임
ip link show type can                  # can0 가 DOWN 상태로 잡혀 있어야 정상

# 2) CAN 올리기 (보율 1Mbps 고정 — Piper 는 이거 외엔 무시)
sudo ./scripts/host-can-up.sh          # modprobe gs_usb + (down 후) up @1000000

# 3) 버스 살아있는지 확인 (팔에 전원 들어간 상태에서)
candump can0                            # 프레임이 좌르륵 흐르면 OK. 아무것도 없으면 §아래 트러블슈팅
ip -details -statistics link show can0  # state UP, ERROR-ACTIVE(정상). BUS-OFF 면 문제
```

> **CAN 은 드라이버 띄우기 전에 호스트에서 올린다.** ROS 노드가 `modprobe` 를 대신 해주지 않으므로, **항상 host 에서 `host-can-up.sh` 먼저** 돌릴 것.

### CAN 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| can0 안 보임 | gs_usb 미로드 / 케이블 | `sudo modprobe gs_usb`, `dmesg \| grep gs_usb`, USB 재삽입 |
| `Operation not permitted` | non-root | `sudo` 로 실행 |
| `Device or resource busy` | 이미 UP 상태 | `sudo ip link set can0 down` 먼저 (host-can-up.sh 가 이제 자동으로 함) |
| candump 무반응 (팔 켜짐) | 포트명 틀림 / 전원 / 케이블 | `ip link show type can` 로 실제 이름 확인 |
| candump 에러 프레임만 | 보율 불일치 | down→up `bitrate 1000000` 재설정 |
| `BUS-OFF` | TX 에러 누적(케이블/종단) | `down && up` 으로 리셋 |
| 재부팅 시 can0/can1 뒤바뀜 | 커널 enumeration 순서 | `agx_arm_ros/scripts/find_all_can_port.sh` 로 USB 경로 확인 → udev `NAME=` 또는 `can_muti_activate.sh` |
| 버스트 시 프레임 드랍 | txqueuelen 작음 | `sudo ip link set can0 txqueuelen 65536` (host-can-up.sh 가 설정) |

---

## 3. 하드웨어 안전 사전점검 (전원 넣기 전)

- [ ] **전원 24 V DC, ≥10 A** (최대 26 V 절대 넘기지 말 것 — 드라이버 파손). 멀티미터로 24.0 V 확인 후 연결. 항공 플러그 빨간점 정렬.
- [ ] **베이스 고정**: 4× **M5** 볼트, 70×70 mm 패턴으로 단단한 면에 고정. **free-standing 금지**(반력 토크).
- [ ] **작업 반경 626 mm 구(球) 비우기**: 팔은 장애물 회피 없음. 사람·물체 치우고, 보안경, 헐렁한 옷/머리 주의. 관절 뜨거움(작동 중·후 1시간 만지지 말 것).
- [ ] **페이로드 1.5 kg 초과 금지**.
- [ ] **물리 E-stop 버튼 없음** ← 첫 구동 땐 **한 사람이 24 V 전원 커넥터에 손 올리고** 즉시 뽑을 준비. (소프트 정지는 `/emergency_stop` 서비스 = 현재 자세 유지)
- [ ] **그리퍼 장착 여부**: 기본은 `effector_type:=agx_gripper`. 그리퍼 없으면 런치 인자를 `effector_type:=none` 으로 주고 띄운다. 안 그러면 gripper_controller 가 안 떠서 arm_controller 까지 막힐 수 있음.

---

## 4. 펌웨어 ↔ URDF 호환 (조용한 위험, 꼭 확인)

펌웨어 버전에 따라 좌표계(DH offset)가 달라서 **MoveIt 이 실제와 다른 위치로 플랜**할 수 있음. RViz 모델과 실제 팔이 어긋나면 "안전해 보이는" 플랜이 자기충돌/리밋으로 갈 수 있음.

- 펌웨어 **≥ S-V1.6-3**: J2/J3 에 2° offset → 기본 `piper_description.urdf`(`dh_is_offset=1`). ← 이 스택이 쓰는 쪽.
- 펌웨어 **< S-V1.6-3**: old DH → `piper_description_old.urdf` / `dh_is_offset=0` 필요. ⚠️ 단 이건 **구 스택(piper_sdk/piper_ros) 레벨 옵션**이고 이 리포의 핀된 `agx_arm_ros` 트리엔 그 파일/플래그가 없음 — 실무적으론 그냥 **펌웨어를 ≥ S-V1.6-3 으로 맞추는 게 답**.
- **권장 ≥ S-V1.8-5**: teach 모드 빠져나올 때 자동 homing 으로 팔이 **드랍하는 위험**이 사라짐(seamless 전환).
- 펌웨어는 **셀프 업데이트 불가** → `support@agilex.ai` 또는 Discord. (Windows "ArmRobotUA" 호스트 SW 경유)

기동 로그에 `firmware version: S-V1.X-X` 가 찍힘 → **≥ S-V1.6-3 인지(URDF 일치), 가능하면 ≥ S-V1.8-5 인지** 확인.

---

## 5. 구동 & 기동 후 health 확인

> ⚠️ **미검증 / 예상 경로**: 아래 실물 런치 커맨드는 서브모듈 런치 파일의 인자로는 확인했지만, **CAN 어댑터를 물려 네이티브로 직접 검증하진 못했다.** 실제 팔에 처음 붙일 땐 로그·컨트롤러 상태를 한 줄씩 확인하며 진행할 것.

```bash
sudo ./scripts/host-can-up.sh        # (이미 했으면 생략)

source /opt/ros/jazzy/setup.bash
source ~/piper-rwh/ros2_ws/install/setup.bash
LC_NUMERIC=C ros2 launch agx_arm_ctrl start_single_agx_arm_moveit.launch.py \
  can_port:=can0 arm_type:=piper effector_type:=agx_gripper
```

> `LC_NUMERIC=C` 는 소수점을 '.' 로 강제해 move_group 의 "expects a double" 파싱 오류를 막는다(네이티브엔 컨테이너 ENV 가 없으니 커맨드에 직접 붙임). 셸에서 `export LC_NUMERIC=C` 해둬도 됨.
> 확인된 런치 인자: `can_port`(기본 can0), `arm_type`(기본 piper), `effector_type`(기본 none — 그리퍼 쓰면 `agx_gripper`), `auto_enable`(기본 true → **기동 즉시 팔이 stiff**), `fast_mode`(기본 false), `speed_percent`(기본 100 — 첫 모션은 ~20 으로 낮출 것), `feedback_topic`(기본 feedback/joint_states), `control_topic`(기본 control/joint_states), `pub_rate`(200), `enable_timeout`(5.0), `follow`(true), `namespace`, `log_level`.

기동 로그에서 **아래가 다 뜰 때까지(~30초) 대기**:
1. `firmware version: S-V1.X-X` (CAN OK)
2. `All joints enable status is True` (모터 **stiff** 됨 — 만지지 말 것)
3. `You can start planning now`

움직이기 **전에** 상태 검증:
```bash
ros2 control list_controllers        # arm_controller / gripper_controller / joint_state_broadcaster = active
ros2 topic echo --once /feedback/joint_states   # NaN 아니고, 값이 실제 팔 자세와 일치해야 함
```
> 피드백 값이 실제 자세와 안 맞으면(팔은 굽었는데 0 으로 읽힘 등) **멈춰라** — master 모드/펌웨어-URDF 불일치/조인트매핑 깨짐(#35/#101) 신호. 잘못된 시작자세로 플랜하지 말 것.
> 실물 피드백은 `/feedback/joint_states`(실제 팔 자세). mock 데모에서 쓰던 `/control/joint_states` 와 헷갈리지 말 것.

---

## 6. 첫 안전 모션 — MoveIt Plan & Execute 만

- 런치가 띄운 **로컬 RViz 창**에서 MotionPlanning 패널 사용
- **Velocity / Acceleration scaling 0.05–0.10** 으로 낮추기 (또는 런치 `speed_percent:=20`)
- Goal State = named **`home`** (전 관절 0). **Plan** → 고스트 궤적 눈으로 확인 → **Execute** (전원 커넥터에 손 올린 채)
- ❌ **첫 구동에 절대 금지**: 컨트롤러에 직접 `ros2 action send_goal`(충돌·리밋 검사 우회), `/control/move_js`·`/control/move_mit`(MIT 토크), `fast_mode:=true`. 전부 안전계층 없음.

> 관절 한계는 **로드된 `piper_description.urdf` 기준**으로 MoveIt 이 강제(대략 J1 ±150°, J2 0–180°, J3 −170–0°, J4 ±100°, J5 ±70°, J6 ±120°). J2/J3 가 한쪽 방향이라 "리밋에서 플랜 거절" 자주 남 — 조인트공간 플래닝으로 시작.

---

## 7. (선택) 분산 실행 (B안)

로컬이 플래닝/RL 에 버거울 때만. **CAN 드라이버는 어댑터 머신 로컬**, MoveIt/RViz/RL 은 다른 PC 에서 LAN 너머 ROS 2 로.

| 양쪽 머신 동일 설정 | 값 |
|---|---|
| `RMW_IMPLEMENTATION` | `rmw_fastrtps_cpp` |
| `ROS_DOMAIN_ID` | 같은 값 (예 42) |
| `FASTDDS_BUILTIN_TRANSPORTS` | `UDPv4` (SHM 은 머신 내부 전용이라 끔) |
| `ROS_STATIC_PEERS` | 상대 머신 LAN IP |
| `ROS_AUTOMATIC_DISCOVERY_RANGE` | `SUBNET` |
| 방화벽 | 양쪽 UFW 가 켜져 있으면 상대 IP 를 명시적으로 허용할 것 — 안 그러면 INPUT 에서 DDS 트래픽이 DROP 되어 노드끼리 서로 안 보임 |
| 네트워크 | **유선 기가비트 필수** (WiFi 금지 — 지터/패킷손실로 제어 깨짐) |
| 시간동기 | 양쪽 `chrony` |

- 어댑터 머신: `host-can-up.sh` 후 위 env 설정 → §5 의 네이티브 런치로 드라이버 기동(ROS 토픽이 LAN 에 노출됨)
- 다른 PC: 같은 env 로 MoveIt/RViz/RL 실행 → `ros2 topic echo /feedback/joint_states` 로 실물 피드백 확인
- **저수준 제어(궤적 실행)는 어댑터 머신에서 로컬 CAN 으로 닫고**, PC 는 고수준 action goal 만 보내는 구조 권장

---

## 8. 종료 순서

1. RViz 로 팔을 **낮게 받쳐진/안정된 rest 자세**로 이동 (⚠️ `home`=전 관절 0 은 곧게 선 자세라 rest 아님 — 여기서 disable 하면 떨어짐). 필요하면 받침대 위로 내리거나 사람이 받친 상태로.
2. `ros2 service call /enable_agx_arm std_srvs/srv/SetBool "{data: false}"` (위 rest 자세에서만 — disable 시 팔 limp 되어 떨어짐)
3. 런치 터미널에서 **Ctrl-C** 로 launch 프로세스 종료 (안 죽으면 `pkill -f start_single_agx_arm_moveit` 로 정리)
4. `sudo ip link set can0 down`
5. 24 V 전원 제거 → CAN USB 분리

> 모션 중/rest 아닌 위치에서 launch 프로세스를 kill 하거나 모터 disable 하지 말 것 — 최저에너지 자세로 떨어져 테이블/자기 자신을 칠 수 있음.

---

## 주요 gotcha 요약

| Gotcha | 결과 | 대응 |
|---|---|---|
| 펌웨어↔URDF DH 불일치(S-V1.6-3) | RViz≠실제, 오플랜 | 펌웨어 버전 ↔ URDF 일치 확인 |
| 물리 E-stop 없음 | 빠른 하드 정지 불가 | 24 V 커넥터에 손 / `/emergency_stop` 소프트정지 |
| `auto_enable` 로 기동 즉시 stiff | 시작 순간 팔 굳음 | 런치 전에 작업공간 비우기 |
| 컨트롤러 직접 goal / MIT / fast_mode | 충돌·리밋 우회 | MoveIt Plan&Execute 만 (첫 구동) |
| 피드백 토픽 `/feedback/joint_states`(`/joint_states` 아님) | 오플랜 | launch 가 remap, 값-자세 일치 확인 |
| CAN bus-off 무음(#109) | 팔 먹통, 에러 안뜸 | 팔+CAN 전원순환, 노드 재시작 |
| master 모드 | 피드백 0, 제어 무시 | slave 모드로 (`MasterSlaveConfig(0xFC,0,0,0)`) |
| 정지 후 enable 1회론 부족 | disable 유지 | reset → enable → enable (2회) |
| `host-can-up.sh` 는 sudo 필요 | 안 하면 can0 안 올라옴 | 드라이버 런치 **전에** `sudo ./scripts/host-can-up.sh` 먼저 |

---

*조사: Sonnet 4명 병렬(호스트요건/CAN/안전절차/아키텍처) → Opus 검수. 출처: AgileX Quick Start Manual V1.0, piper_sdk·agx_arm_ros·piper_ros, Reimagine-Robotics/piper_control, SDK issues #35/#96/#101/#109. 자세한 레퍼런스는 [references.md](references.md).*
</content>
</invoke>
