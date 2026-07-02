# Piper SDK 사용 가이드 (설치 → 세팅 → 실행 → 제어)

AgileX **Piper 6-DOF 로봇팔**을 `piper_sdk`(Python)로 직접 점검·제어하는 실전 가이드.
실측으로 검증한 절차와 **이 펌웨어(S-V1.7-3)의 함정**까지 담았다.

> ROS2/MoveIt 없이 **SDK만으로** 상태확인·관절/그리퍼 제어를 하는 경로다.
> ROS2 스택으로 갈 거면 [`real-robot-checklist.md`](real-robot-checklist.md) 참고.
>
> ⚠️ **여기 쓰는 `piper_sdk` 는 구 스택(Piper 전용)이다.** 진단·단독 제어용으로만 쓴다. 이 리포의
> ROS 2 네이티브 스택이 실제로 까는 건 그 후속인 **`pyAgxArm`**(신 스택) 이다 — 둘은 다른 패키지다.
> 구/신 스택 구분은 [`references.md`](references.md) 참고.

---

## 0. 현재 장비 정보 (이 환경 기준)

> ⚠️ 아래 표는 **머신이 두 개** 섞여 있다. OS/Python 은 **이 머신(24.04 노트북)** 실측이고,
> 팔 개수·펌웨어·SDK 버전은 **다른 머신(22.04, 2팔 세션)** 실측이라 이 머신에서 **재확인 전까지는 그대로 못 믿는다**.
> 표에 (이 머신) / (재확인 필요) 로 출처를 박아둠.

| 항목 | 값 | 출처 |
|---|---|---|
| OS / Python | Ubuntu 24.04.4 / Python 3.12 | 이 머신 |
| SDK | **이 머신엔 `piper_sdk` 미설치** (22.04 머신엔 0.4.1 이 `~/.local/lib/python3.10/site-packages/piper_sdk` 에 있었음) | 재확인 필요 |
| CAN 어댑터 | gs_usb (candleLight) `1d50:606f` | 재확인 필요 |
| 보율(bitrate) | **1 Mbps (1000000)** ← Piper 고정, 이거 외엔 무시됨 | Piper 스펙 |
| 로봇 | 팔 **2대** (can0=암#1, can1=암#2) — 이 머신엔 지금 CAN 어댑터/팔 안 붙어 있음 | 재확인 필요 |
| 펌웨어 | **S-V1.7-3** (22.04 세션 실측, 양쪽 동일) | 재확인 필요 |

⚠️ **펌웨어 S-V1.7-3 한계**: teach 모드를 빠져나올 때 토크가 풀려 **팔이 떨어진다(drop)**.
seamless 전환(드랍 없음)은 **≥ S-V1.8-5** 부터. 근본 해결은 펌웨어 업그레이드(셀프 불가 → `support@agilex.ai`).
👉 단, 이 drop 경고는 **펌웨어가 S-V1.7-3 일 때만** 유효하다. 이 머신에 붙일 실물 펌웨어를 먼저 확인하고,
S-V1.8-5 이상이면 이 항 자체가 해당 안 될 수 있으니 표의 펌웨어 값부터 재확인할 것.

---

## 1. 설치

```bash
pip3 install --user --break-system-packages piper_sdk   # python-can 자동 설치됨
sudo apt install -y can-utils                           # candump/cansend (진단용)
```
> 24.04(PEP668, externally-managed)에선 `--user` 만으론 거부된다 → `--user` 와 `--break-system-packages` 를 **둘 다** 붙여야 `~/.local` 에 깔린다(sudo 아님).

SDK 안에 공식 헬퍼 스크립트/데모 포함:
`find_all_can_port.sh`, `can_activate.sh`, `demo/V2/piper_ctrl_*.py`, `demo/detect_arm.py`

---

## 2. 하드웨어 연결 & 전원

- Piper는 **전원/통신이 같은 항공 커넥터** 한 개로 나온다. 케이블에서 갈라져:
  - 빨강(VCC)/검정(GND) → **24V, ≥10A** 전원 어댑터 (26V 초과 금지)
  - 노랑(CAN_H)/파랑(CAN_L) → **USB-to-CAN 모듈**
- **별도 전원 버튼 없음**: 24V 인가 = 전원 ON. **물리 E-stop 버튼도 없음.**
- 전원 확인: **베이스 전기 패널의 status 표시등** (J5–J6 사이 티치버튼 불 아님).
- 항공 커넥터는 **빨간 점 정렬 후 끝까지** 꽂을 것.

---

## 3. CAN 올리기 (호스트에서, 1회)

```bash
sudo ip link set can0 down 2>/dev/null
sudo ip link set can0 up type can bitrate 1000000
sudo ip link set can0 txqueuelen 65536
# can1도 동일하게 (2대 쓸 때)
```
확인:
```bash
ip -details link show can0          # state UP, ERROR-ACTIVE, bitrate 1000000
candump can0                        # 팔 켜졌으면 프레임이 좌르륵 흐름
```
> **프레임이 없으면** = 전원 안 들어옴 / CAN선 미연결 / 보율 불일치. 에러프레임만 쌓이면 보율(1Mbps) 재확인.

---

## 4. 상태 읽기 (read-only, 안전)

```python
import time
from piper_sdk import C_PiperInterface_V2

p = C_PiperInterface_V2("can0")     # 2번째 팔은 "can1"
p.ConnectPort(); time.sleep(0.5)

print(p.GetArmStatus())             # ctrl_mode / teach_status / arm_status / err_code
print(p.GetArmJointMsgs())          # 관절 (단위 0.001°)
print(p.GetArmEndPoseMsgs())        # 엔드포즈 (X/Y/Z 0.001mm, RX/RY/RZ 0.001°)
print(p.GetArmGripperMsgs())        # 그리퍼 (각도 0.001mm, 토크 0.001 N/m)
p.SearchPiperFirmwareVersion(); time.sleep(0.5)
print(p.GetPiperFirmwareVersion())
```
정상 신호: `arm_status: NORMAL`, `err_code: 0`, 피드백 `Hz ~200`.

**단위 요약**: 관절·자세각 = **0.001°**, 위치 = **0.001mm**, 그리퍼 토크 = **0.001 N/m** (범위 0~5000).

**관절 한계**: J1 ±150 / **J2 0~180** / **J3 -170~0** / J4 ±100 / J5 ±70 / J6 ±120 (deg).

---

## 5. 제어 (검증된 안전 절차)

### 5-1. 모드 개념
- `ctrl_mode`: **STANDBY(0x0)** / **CAN_CTRL(0x1)** / **TEACHING_MODE(0x2)**
- `teach_status`: **DISABLED(0x0)** / START_RECORDING(0x1) / **STOP_RECORDING(0x2)**
- **제어하려면 `teach_status == DISABLED` 인 상태에서 CAN_CTRL로 전환해야 한다.**

### 5-2. 핵심 시퀀스 (이 개체에서 검증된 순서)
1. **클린 상태 확인** (`teach=DISABLED`, `arm=NORMAL`, `err=0`)
2. **CAN 전환을 모터 disable 상태에서 먼저** (`MotionCtrl_2(0x01,...)`) ← enable 먼저 하면 전환 실패함
3. **enable** (`EnableArm(7)`, 전부 True 될 때까지) → 현 자세 stiff 홀딩
4. **현재 관절값 읽어서 그 값 기준으로** `MotionCtrl_2`+`JointCtrl`를 **~100–200Hz로 연속 전송** (멈추면 STANDBY로 회귀 → 토크 풀림)

### 5-3. 안전 규칙 (필수)
- 🚫 **절대좌표 금지.** `JointCtrl(0,0,0,0,0,x)` = 전 관절 0으로 휙 → 위험. **항상 현재값을 읽어 상대(delta)로**.
- ✅ 첫 동작은 **저속(`move_spd_rate=20`)**, setpoint를 잘게 램프해 천천히.
- ✅ **freshness 게이트**: `Hz>0 && time_stamp!=0` 확인 후에만 값 신뢰 (안 하면 기본값 0을 읽어 절대0 돌진).
- ✅ **관절 sanity 체크**: 범위 밖 값(예: J2 -364°)이면 중단 → 전원 재인가.
- ✅ `move_mode=0x01`(MOVE_J), `is_mit_mode=0x00`. **MIT(0xAD) 금지** (토크직접, 안전계층 없음).
- ✅ 동작 중 `arm_status`/`err_code` 실시간 감시, 이상 시 즉시 중단.
- 🚫 **공중/불안정 자세에서 disable 금지** — 토크 풀려 떨어짐.

### 5-4. 최소 예제 — J6만 상대 +8° 후 복귀 (다른 관절 고정)
> 이 예제는 §5-3 안전규칙(freshness·sanity·fault감시·안전종료)을 **모두 포함**한다. 줄여 쓰지 말 것.

```python
import time, sys
from piper_sdk import C_PiperInterface_V2
p = C_PiperInterface_V2("can0"); p.ConnectPort()

# 1) freshness 게이트: 실제 프레임 도착 후에만 값 신뢰 (기본값 0 → 절대0 돌진 방지)
t0=time.time()
while True:
    st=p.GetArmStatus(); jm=p.GetArmJointMsgs()
    if st.Hz>0 and jm.Hz>0 and st.time_stamp!=0 and jm.time_stamp!=0: break
    if time.time()-t0>3.0: sys.exit("ABORT: CAN 피드백 없음")
    time.sleep(0.02)
s=st.arm_status
assert int(s.teach_status)==0, "teach!=DISABLED → §6-1 복구 먼저 (STOP_RECORDING이면 CAN전환 거부됨)"
assert int(s.arm_status)==0 and int(s.err_code)==0, "arm fault/err → 해결 후 진행"

# 2) CAN 전환(모터 disable 상태에서 먼저) — 타임아웃 포함
p.MotionCtrl_2(0x00,0x01,20,0x00); time.sleep(0.2)            # move_spd_rate_ctrl=20(%)
t0=time.time()
while int(p.GetArmStatus().arm_status.ctrl_mode)!=1:
    p.MotionCtrl_2(0x01,0x01,20,0x00); time.sleep(0.15)
    if time.time()-t0>4.0: sys.exit("ABORT: CAN 전환 실패(teach latch 의심 → §6-1)")
# 3) enable(현 자세 홀딩) — 타임아웃 포함
t0=time.time()
while not all(p.GetArmEnableStatus()):
    p.EnableArm(7); time.sleep(0.1)
    if time.time()-t0>5.0: sys.exit("ABORT: enable 타임아웃")

# 4) 현재값 읽기 + 관절 sanity (범위 밖이면 중단)
j=p.GetArmJointMsgs().joint_state
base=[j.joint_1,j.joint_2,j.joint_3,j.joint_4,j.joint_5,j.joint_6]
LIM=[(-155,155),(-6,186),(-176,6),(-105,105),(-75,75),(-125,125)]   # deg, 여유 포함
for i,(v,(lo,hi)) in enumerate(zip([x/1000 for x in base],LIM)):
    if not lo<=v<=hi: sys.exit(f"ABORT: J{i+1}={v}° 범위 밖 → 전원 재인가(§6-2)")
j6=base[5]; clamp=lambda v:max(-120000,min(120000,int(v)))

# 5) J6만 상대 램프 (~100Hz 연속 스트림 + 동작 중 fault 감시)
def ramp(t,secs=4.0,hz=100):
    n=int(secs*hz); s0=ramp.cur
    for k in range(n):
        a=p.GetArmStatus().arm_status
        if int(a.arm_status)!=0 or int(a.err_code)!=0: raise RuntimeError("동작 중 fault → 중단")
        v=clamp(s0+(t-s0)*(k+1)/n)
        p.MotionCtrl_2(0x01,0x01,20,0x00)
        p.JointCtrl(base[0],base[1],base[2],base[3],base[4],v)   # j1~j5 고정, j6만
        time.sleep(1/hz)
    ramp.cur=t
ramp.cur=j6
try:
    ramp(j6+8000)     # +8°
    ramp(j6)          # 복귀
finally:
    # 스트림이 끊기면 STANDBY로 회귀→토크 풀림→드랍. 종료 시 1초간 현 자세를 잡아준다.
    for _ in range(100):
        p.MotionCtrl_2(0x01,0x01,20,0x00)
        p.JointCtrl(base[0],base[1],base[2],base[3],base[4],clamp(ramp.cur)); time.sleep(0.01)
```

### 5-5. 그리퍼만 (팔 관절 enable 불필요, 단 CAN_CTRL 필요)
> 이 세션 실측: **CAN_CTRL + 관절 disable([False]×6) 상태에서 그리퍼 단독 동작 확인**. 공식 데모는 `EnablePiper()`(전체 enable) 후 제어하니, 팔도 stiff하게 두려면 그쪽을 따른다.
```python
# CAN_CTRL 상태에서:  각도(0.001mm), 토크(0.001 N/m, 저토크 500), 0x01=enable
p.GripperCtrl(10000, 500, 0x01, 0)   # ~10mm 벌림
p.GripperCtrl(0,     500, 0x01, 0)   # 닫기
```

---

## 6. 트러블슈팅 / 주의사항

### 6-1. ⚠️ teach 버튼 누르면 SDK 제어가 막힌다 (그리고 복구 시 팔이 떨어진다)
- 티치 버튼으로 녹화를 껐다 켜면 `teach_status`가 **`STOP_RECORDING(0x2)`로 latch** → **CAN 전환 거부됨**.
- **소프트 복구** (전원 안 꺼도 됨):
  ```python
  for _ in range(8):
      p.MotionCtrl_1(0x02,0,0)          # emergency_stop = RESUME
      p.MotionCtrl_2(0x00,0x01,20,0x00) # STANDBY
      time.sleep(0.5)
      if int(p.GetArmStatus().arm_status.teach_status)==0: break
  ```
- 🚨 **이 복구는 STANDBY를 거치며 토크를 푼다 → S-V1.7-3에선 팔이 "푹" 떨어진다.**
  반드시 **팔을 손으로 받치거나 낮은 자세**로 둔 상태에서 복구할 것.
- ✅ **가장 좋은 회피책: SDK 세션 중엔 teach 버튼을 아예 누르지 말 것.** 드랍은 *teach 탈출 시에만* 발생한다. 세션마다 수동(teach) **또는** SDK(CAN) 중 하나만 쓴다.

### 6-2. 관절값이 범위 밖으로 읽힘 (예: J2 -364°)
- 극단 자세에서 enable/teach 반복 시 **엔코더 멀티턴 카운터가 어긋날 수 있음**.
- 이 상태로 제어하면 위험 → **전원 재인가(24V 분리·재연결)로 리셋** (부팅 시 정상범위 복귀). 재인가 전 팔 받칠 것.

### 6-3. 명령을 보내는데 안 움직임
- **연속 전송 안 함**: `MotionCtrl_2`+`JointCtrl`를 ~100–200Hz 루프로 계속 보내야 한다(단발 무시됨).
- **모드 안 맞음**: `ctrl_mode != CAN_CTRL`. §5-2 / §6-1 확인.
- **그리퍼/관절 enable 안 됨**: 관절은 `EnableArm(7)`, 그리퍼는 `GripperCtrl(...,0x01,...)`.

### 6-4. 2대(can0/can1) 구분 / 재부팅 시 뒤바뀜
- USB enumeration 순서에 따라 can0/can1이 바뀔 수 있음 → `find_all_can_port.sh`(sudo)로 USB 경로 확인 후 udev 고정 권장.

### 6-5. 안전 종료 순서
1. 팔을 **낮고 안정된 자세**로 (RViz/수동)
2. (받쳐진 상태에서) `p.MotionCtrl_2(0x00,...)` → `p.DisablePiper()`  ← disable 시 토크 풀림 주의
3. `sudo ip link set can0 down` → 24V 분리

---

## 7. 한 줄 요약 (체크리스트)

- [ ] 24V(≥10A) 인가 + CAN선 연결 → 베이스 status등 ON
- [ ] `sudo ip link ... bitrate 1000000` → `candump can0` 프레임 확인
- [ ] SDK로 상태 읽기: `arm_status NORMAL`, `err 0`, `Hz ~200`
- [ ] 제어: **teach=DISABLED** → CAN전환(disable먼저) → enable → **200Hz 연속 스트림**
- [ ] **절대좌표 금지·상대이동·저속·freshness/sanity 게이트**
- [ ] teach 버튼은 SDK 세션 중 만지지 말기 (S-V1.7-3 드랍 이슈)
- [ ] 근본해결: 펌웨어 **≥ S-V1.8-5** 업그레이드 (AgileX 문의)

*검증: 2026-06, can0/can1 실측 (상태확인·J6 상대이동·그리퍼·teach 복구). **단 이 검증은 22.04 노트북 + 2팔(can0/can1) 세션 기준이다** — 지금 이 머신(24.04)에선 아직 재확인 안 됐으니 §0 표의 출처 표기를 보고, 실물 붙이면 펌웨어·팔 개수부터 다시 확인할 것. 출처: piper_sdk 0.4.1 데모/인터페이스, piper_ros 드라이버, piper_sdk issue #11, AgileX Quick Start Manual V1.0.*
