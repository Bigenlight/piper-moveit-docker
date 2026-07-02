#!/usr/bin/env python3
"""
예제 2: pymoveit2 중급 클라이언트 (Cartesian 경로 + 플래닝 씬 장애물)

무엇을 보여주나:
  1) IK 로 푸는 Cartesian POSE 목표 (자유공간 계획)
  2) 직선 CARTESIAN PATH (엔드이펙터가 직선으로 이동)
  3) 플래닝 씬 충돌 박스 추가 -> 우회 계획 -> 제거
  4) 속도/가속 스케일링

실행 (먼저 mock move_group 가 떠 있어야 함):
  터미널 A:  ./scripts/run-mock.sh        # "You can start planning now!" 뜰 때까지 대기
  터미널 B:
    source /opt/ros/jazzy/setup.bash
    source ~/piper-rwh/ros2_ws/install/setup.bash
    python3 examples/python/ex02_pymoveit2_cartesian_scene.py

필요 패키지:  sudo apt install ros-jazzy-pymoveit2

주의: mock 은 관절 피드백을 /control/joint_states 로 낸다. pymoveit2 는 '/joint_states' 를
구독하므로 아래 rclpy.init 에서 리맵한다(안 하면 plan() 이 현재자세를 못 받아 무한 대기).
"""

import sys
import time
from threading import Thread

import rclpy
from rclpy.node import Node
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import MultiThreadedExecutor

from pymoveit2 import MoveIt2

# SRDF 기준 arm 그룹 정의 (base_link -> tcp_link, 6-DOF)
ARM_JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]
BASE_LINK = "base_link"
EE_LINK = "tcp_link"
GROUP = "arm"

# FK 로 실측한 '도달 보장' 포즈 (base_link 기준). 각 포즈는 어떤 관절자세의 FK 결과라
# IK 해가 존재함이 보장됨 -> 계획 실패를 피함. (position, quat_xyzw)
POSE_A = ([0.1158, 0.0000, 0.3133], [0.0000, 0.8633, 0.0000, 0.5047])    # 정면
POSE_B = ([0.1067, 0.0451, 0.3133], [-0.1715, 0.8461, 0.1003, 0.4946])   # 좌측 (직선 경로 목표)
POSE_C = ([0.1067, -0.0451, 0.3133], [0.1715, 0.8461, -0.1003, 0.4946])  # 우측 (장애물 우회 목표)


def main():
    # mock 의 /control/joint_states 를 pymoveit2 가 구독하는 /joint_states 로 리맵
    rclpy.init(args=sys.argv + ["--ros-args", "-r", "joint_states:=/control/joint_states"])
    node = Node("ex02_pymoveit2_cartesian_scene")
    cb = ReentrantCallbackGroup()

    moveit2 = MoveIt2(
        node=node,
        joint_names=ARM_JOINTS,
        base_link_name=BASE_LINK,
        end_effector_name=EE_LINK,
        group_name=GROUP,
        callback_group=cb,
    )

    # 별도 스레드에서 executor 스핀 (move_to_* 는 블로킹 호출)
    executor = MultiThreadedExecutor(2)
    executor.add_node(node)
    executor_thread = Thread(target=executor.spin, daemon=True)
    executor_thread.start()
    time.sleep(1.0)  # 액션/토픽 연결 대기

    # 부드럽게 움직이도록 속도/가속 스케일 낮춤 (0..1)
    moveit2.max_velocity = 0.3
    moveit2.max_acceleration = 0.3

    # 0) 안전한 시작 자세 (SRDF home = 전 관절 0.0)
    node.get_logger().info("[0] home 자세로 이동")
    moveit2.move_to_configuration([0.0] * 6)
    moveit2.wait_until_executed()

    # 1) POSE 목표: IK 로 풀어 자유공간(관절공간) 계획
    node.get_logger().info(f"[1] POSE 목표(자유공간, cartesian=False) -> {POSE_A[0]}")
    moveit2.move_to_pose(position=POSE_A[0], quat_xyzw=POSE_A[1], cartesian=False)
    moveit2.wait_until_executed()

    # 2) 직선 CARTESIAN PATH: 엔드이펙터가 직선으로 이동(TCP 궤적이 곧게 유지됨).
    #    자유공간 계획과 달리 경로 형상이 보장됨. max_step 은 보간 간격.
    node.get_logger().info(f"[2] 직선 경로(cartesian=True) -> {POSE_B[0]}")
    moveit2.move_to_pose(
        position=POSE_B[0],
        quat_xyzw=POSE_B[1],
        cartesian=True,
        cartesian_max_step=0.0025,
        cartesian_fraction_threshold=0.0,  # 0 이면 부분 경로도 허용
    )
    moveit2.wait_until_executed()

    # 3) 플래닝 씬 장애물: 씬에 박스를 추가하면 이후 모든 계획이 이를 충돌로 간주한다.
    #    여기선 팔 위쪽 '천장' 박스를 놓아 계획이 이를 회피(위로 안 뻗음)하도록 함 -> 제거.
    box_id = "ceiling_box"
    box_pos = [0.12, 0.0, 0.50]  # 팔 작업영역 위쪽 (도달 자세와 겹치지 않게)
    node.get_logger().info("[3] 충돌 박스(천장) 추가 후 우측 목표로 계획")
    moveit2.add_collision_box(
        id=box_id,
        size=(0.40, 0.40, 0.05),
        position=box_pos,
        quat_xyzw=[0.0, 0.0, 0.0, 1.0],
        frame_id=BASE_LINK,
    )
    time.sleep(0.5)  # 씬 갱신 반영 대기

    moveit2.move_to_pose(position=POSE_C[0], quat_xyzw=POSE_C[1], cartesian=False)
    moveit2.wait_until_executed()

    node.get_logger().info("[3] 충돌 박스 제거")
    moveit2.remove_collision_object(id=box_id)
    time.sleep(0.5)

    # 4) 마무리: home 복귀
    node.get_logger().info("[4] home 복귀")
    moveit2.move_to_configuration([0.0] * 6)
    moveit2.wait_until_executed()

    node.get_logger().info("완료")
    # 스핀 중인 executor 를 먼저 멈추고 join -> 종료 시 crash 방지
    executor.shutdown()
    executor_thread.join(timeout=2.0)
    rclpy.shutdown()


if __name__ == "__main__":
    main()
