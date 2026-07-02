#!/usr/bin/env python3
"""ex01_pymoveit2_basic.py — pymoveit2 로 Piper 를 움직이는 가장 기본적인 예제.

이미 떠 있는 move_group 에 붙는 "클라이언트" 다. 먼저 별도 터미널에서 mock 을 띄운다:
    ./scripts/run-mock.sh
로그에 "You can start planning now!" 가 뜨면 다른 터미널에서:
    source /opt/ros/jazzy/setup.bash
    source ~/piper-rwh/ros2_ws/install/setup.bash
    python3 examples/python/ex01_pymoveit2_basic.py

보여주는 것:
  1) 관절공간 목표(move_to_configuration) 로 안전한 자세 이동
  2) 홈(전관절 0.0) 복귀  — pymoveit2 는 SRDF 상태명이 아닌 '관절값' 을 목표로 준다
  3) 그리퍼 열기/닫기 — gripper_controller 는 JointTrajectoryController 라
     GripperInterface(GripperCommand) 대신 group_name="gripper" 인 두 번째 MoveIt2 인스턴스로 제어
  4) 속도/가속 스케일링을 완만한 값으로 설정

사전 설치: sudo apt install ros-jazzy-pymoveit2

주의: mock(run-mock.sh)은 관절 피드백을 /control/joint_states 로 낸다. pymoveit2 는
'/joint_states' 를 구독하므로, 아래 rclpy.init 에서 그 구독을 /control/joint_states 로
리맵한다(안 하면 plan() 이 현재자세를 못 받아 무한 대기). 실기/다른 셋업이면 이 리맵을 조정.
"""

import sys
from threading import Thread

import rclpy
from rclpy.node import Node
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import MultiThreadedExecutor

from pymoveit2 import MoveIt2

# 팔 관절 순서(SRDF 체인 base_link -> tcp_link)
ARM_JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]


def main():
    # mock 의 /control/joint_states 를 pymoveit2 가 구독하는 /joint_states 로 리맵
    rclpy.init(args=sys.argv + ["--ros-args", "-r", "joint_states:=/control/joint_states"])
    node = Node("ex01_pymoveit2_basic")

    # 콜백 그룹 하나로 팔/그리퍼 인터페이스를 공유
    cb = ReentrantCallbackGroup()

    # 팔 인터페이스
    arm = MoveIt2(
        node=node,
        joint_names=ARM_JOINTS,
        base_link_name="base_link",
        end_effector_name="tcp_link",
        group_name="arm",
        callback_group=cb,
    )

    # 그리퍼 인터페이스(별도 그룹/관절). GripperCommand 가 아니라 궤적 컨트롤러라서 이렇게 붙인다.
    gripper = MoveIt2(
        node=node,
        joint_names=["gripper"],
        base_link_name="base_link",
        end_effector_name="tcp_link",
        group_name="gripper",
        callback_group=cb,
    )

    # 완만하게 (0..1 스케일). 처음 돌릴 땐 천천히.
    arm.max_velocity = 0.2
    arm.max_acceleration = 0.2
    gripper.max_velocity = 0.2
    gripper.max_acceleration = 0.2

    # executor 를 데몬 스레드에서 스핀 -> move_to_* 는 블로킹 없이 액션을 진행
    executor = MultiThreadedExecutor(2)
    executor.add_node(node)
    executor_thread = Thread(target=executor.spin, daemon=True)
    executor_thread.start()

    try:
        # 1) 관절공간 목표: 한계 안쪽의 완만한 자세
        node.get_logger().info("팔: 안전 자세로 이동")
        arm.move_to_configuration([0.0, 0.5, -0.5, 0.0, 0.5, 0.0])
        arm.wait_until_executed()

        # 2) 홈 복귀(전관절 0.0). SRDF 의 'home' 상태와 동일한 값이지만 여기선 값으로 지정.
        node.get_logger().info("팔: 홈(전관절 0) 복귀")
        arm.move_to_configuration([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
        arm.wait_until_executed()

        # 3) 그리퍼 열기 -> 닫기 (open=0.1, close=0.0)
        node.get_logger().info("그리퍼: 열기")
        gripper.move_to_configuration([0.1])
        gripper.wait_until_executed()

        node.get_logger().info("그리퍼: 닫기")
        gripper.move_to_configuration([0.0])
        gripper.wait_until_executed()

        node.get_logger().info("완료")
    finally:
        # 스핀 중인 executor 를 먼저 멈추고 join -> 종료 시 crash 방지
        executor.shutdown()
        executor_thread.join(timeout=2.0)
        rclpy.shutdown()


if __name__ == "__main__":
    main()
