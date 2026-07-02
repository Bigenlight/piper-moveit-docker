# legacy/docker — Docker 시절 아카이브

이 리포는 원래 "Piper MoveIt Docker"였습니다. Tiryoh의 ros2-desktop-vnc:jazzy 이미지를 베이스로, MoveIt2 + ros2_control + agx_arm_ros 스택을 컨테이너에 담아 브라우저(noVNC, localhost:6080)로 조작하는 구성이었어요. 지금은 호스트에 ROS 2 Jazzy를 직접 설치한 네이티브 구성으로 전환했고(루트 README 참고), 여기 파일들은 기록용으로만 보관합니다. 유지보수하지 않습니다.

## 뭐가 들어있나

- `Dockerfile` — 베이스 이미지 위에 apt 패키지 + pyAgxArm(SHA 핀) 설치, colcon 빌드, noVNC/supervisor 연결.
- `docker-compose.yml` — 5개 프로파일: `mock`(가짜 하드웨어 데모), `real`(host-net + privileged + /dev 로 실물 CAN), `direct`(전용 bridge 172.28.0.0/16 으로 호스트↔컨테이너 DDS 연결), `dev`(ros2_ws 바인드 마운트 개발 셸), `gpu`(nvidia-container-toolkit).
- `entrypoint.sh` — MODE(mock/real/dev) 분기 디스패처. supervisord 가 `novnc/ros-app.conf` 로 실행.
- `novnc/desktop-realfix.*` — real 프로파일이 host-network 라 호스트 X :1 과 충돌 → 컨테이너 데스크탑을 VNC :2 / noVNC 6080 으로 재배치하던 픽스.
- `scripts/host-ros-env.sh` + `scripts/setup-host-firewall.sh` — `direct` 프로파일 전용 한 쌍. 호스트 셸에 DDS 환경변수(도메인 42, static peer 172.28.0.2)를 심고 UFW 에 브리지 서브넷 허용 규칙을 넣던 것. 네이티브에선 컨테이너가 없으니 존재 이유가 없음.
- `docs/direct-profile-safety.md` — direct 프로파일이 기존 호스트 ROS 를 안 건드린다는 실측 근거 문서.
- `versions.env` — 당시 핀 전문(이미지 좌표 OWNER/IMAGE_*/BASE_IMAGE digest 포함). AgileX 핀 두 개(AGX_ARM_ROS_SHA, PYAGXARM_SHA)는 네이티브에서도 유효해서 루트 `versions.env` 에 살아있습니다.
- `github-workflows-build.yml` — GHCR 자동 빌드/푸시 CI. `.github/workflows/` 밖으로 옮긴 시점부터 실행 안 됨(주간 재빌드 포함, 의도된 중단).
- `SPEC.md` — 이 아카이브 세트를 만들 때 쓴 저작 계약 원본.

## 예전엔 어떻게 돌았나

```bash
docker build -t piper-moveit:jazzy .          # 또는 ghcr.io 에서 pull
docker compose up mock                        # → 브라우저 http://localhost:6080
sudo ./scripts/host-can-up.sh && docker compose --profile real up   # 실물
```

## 주의

- 여기서 `docker build` 를 다시 돌려도 안 됩니다: 빌드 컨텍스트가 리포 루트 기준(`COPY ros2_ws/src ...`, `COPY novnc/ ...`)이라 경로가 어긋나고, CI 도 꺼져 있어요. 부활시키려면 파일들을 루트로 되돌리는 게 빠릅니다.
- `scripts/host-can-up.sh` 는 여기 없습니다 — 호스트측 CAN bring-up 은 네이티브에서도 그대로 필요해서 루트 `scripts/` 에 남아 있습니다.
- 베이스 이미지 출처: [Tiryoh/docker-ros2-desktop-vnc](https://github.com/Tiryoh/docker-ros2-desktop-vnc) (Apache-2.0).