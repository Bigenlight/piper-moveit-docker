#!/usr/bin/env python3
"""예제 3/3 — 공식 파이썬 바인딩 moveit_py (모듈 "moveit", 클래스 MoveItPy).

pymoveit2(예제 1·2)는 별도로 떠 있는 move_group 에 붙는 "클라이언트"지만,
MoveItPy 는 자기 프로세스 안에서 move_group 을 직접 띄운다(in-process).
따라서 이 예제는 반드시 전용 런치로 실행해야 하며, run-mock.sh(demo.launch.py)와
동시에 돌리면 move_group 이 두 개가 되어 충돌한다. 단독 실행할 것.

사전 준비:
  sudo apt install ros-jazzy-moveit-py     # import 이름은 "moveit"
  cd ~/piper-rwh/ros2_ws && colcon build && source install/setup.bash

실행(이 파일이 아니라 런치를 실행한다 — 런치가 이 스크립트를 노드로 띄운다):
  source /opt/ros/jazzy/setup.bash
  source ~/piper-rwh/ros2_ws/install/setup.bash
  LC_NUMERIC=C ros2 launch ~/piper-rwh/examples/python/ex03_moveit_py.launch.py

보여주는 것(공식 API 강점):
  1. get_planning_component + set_start_state_to_current_state
  2. SRDF 이름 상태로 계획·실행: set_goal_state(configuration_name="home")  ← pymoveit2 대비 핵심 강점
  3. 대조용 비이름 목표(관절 목표 + 포즈 목표)
  4. planning_scene_monitor read_write 로 충돌물체 추가 후 회피 계획
  5. MultiPipelinePlanRequestParameters 다중 파이프라인 계획(런치에서 파이프라인 설정 필요)
"""

import os
import time

from geometry_msgs.msg import Pose, PoseStamped
from moveit.core.kinematic_constraints import construct_joint_constraint
from moveit.core.robot_state import RobotState
from moveit.planning import MoveItPy, MultiPipelinePlanRequestParameters
from moveit_msgs.msg import CollisionObject
from rclpy.logging import get_logger
from shape_msgs.msg import SolidPrimitive

ARM_GROUP = "arm"
TIP_LINK = "tcp_link"
BASE_LINK = "base_link"


def plan_and_execute(robot, component, logger,
                     single_plan_parameters=None,
                     multi_plan_parameters=None,
                     sleep_time=0.0):
    """공식 튜토리얼과 동일한 계획→실행 헬퍼."""
    logger.info("계획 중...")
    if multi_plan_parameters is not None:
        result = component.plan(multi_plan_parameters=multi_plan_parameters)
    elif single_plan_parameters is not None:
        result = component.plan(single_plan_parameters=single_plan_parameters)
    else:
        result = component.plan()

    if result:
        logger.info("실행 중...")
        robot.execute(result.trajectory, controllers=[])  # controllers=[] → 자동 선택
    else:
        logger.error("계획 실패")
    time.sleep(sleep_time)
    return bool(result)


BOX_ID = "obstacle_box"


def add_ground_box(robot, logger):
    """planning_scene_monitor 의 read_write 컨텍스트로 충돌물체를 씬에 직접 추가.
    home(수직) 자세나 목표를 막지 않도록 옆쪽(+y)에 배치 -> 계획은 이를 인지하되 성공."""
    psm = robot.get_planning_scene_monitor()
    with psm.read_write() as scene:
        obj = CollisionObject()
        obj.header.frame_id = BASE_LINK
        obj.id = BOX_ID

        box = SolidPrimitive()
        box.type = SolidPrimitive.BOX
        box.dimensions = [0.1, 0.1, 0.2]

        pose = Pose()
        pose.position.x = 0.0
        pose.position.y = 0.30  # 팔 작업영역 옆
        pose.position.z = 0.20
        pose.orientation.w = 1.0

        obj.primitives.append(box)
        obj.primitive_poses.append(pose)
        obj.operation = CollisionObject.ADD

        scene.apply_collision_object(obj)
        scene.current_state.update()  # 씬 상태 갱신 필수
    logger.info(f"충돌물체 '{BOX_ID}' 추가 완료")


def remove_ground_box(robot, logger):
    """추가했던 충돌물체를 씬에서 제거(operation=REMOVE)."""
    psm = robot.get_planning_scene_monitor()
    with psm.read_write() as scene:
        obj = CollisionObject()
        obj.header.frame_id = BASE_LINK
        obj.id = BOX_ID
        obj.operation = CollisionObject.REMOVE
        scene.apply_collision_object(obj)
        scene.current_state.update()
    logger.info(f"충돌물체 '{BOX_ID}' 제거 완료")


def main():
    logger = get_logger("ex03_moveit_py")

    # MoveItPy 가 in-process move_group 을 띄운다. 파라미터는 런치에서 주입됨.
    robot = MoveItPy(node_name="moveit_py")
    arm = robot.get_planning_component(ARM_GROUP)
    robot_model = robot.get_robot_model()

    # --- 1) SRDF 이름 상태 "home" (모든 관절 0.0) ---
    arm.set_start_state_to_current_state()
    arm.set_goal_state(configuration_name="home")  # ← 공식 바인딩의 핵심 강점
    plan_and_execute(robot, arm, logger, sleep_time=1.0)

    # --- 2a) 대조: 관절 목표(RobotState + joint constraint) ---
    arm.set_start_state_to_current_state()
    goal_state = RobotState(robot_model)
    goal_state.joint_positions = {
        "joint1": 0.3, "joint2": 0.4, "joint3": -0.4,
        "joint4": 0.0, "joint5": 0.6, "joint6": 0.0,
    }
    jc = construct_joint_constraint(
        robot_state=goal_state,
        joint_model_group=robot_model.get_joint_model_group(ARM_GROUP),
    )
    arm.set_goal_state(motion_plan_constraints=[jc])
    plan_and_execute(robot, arm, logger, sleep_time=1.0)

    # --- 2b) 대조: 포즈 목표(IK) ---
    # 포즈/방향은 FK 로 실측한 '도달 보장' 값 (어떤 관절자세의 FK 라 IK 해가 존재).
    arm.set_start_state_to_current_state()
    pose = PoseStamped()
    pose.header.frame_id = BASE_LINK
    pose.pose.position.x = 0.1158
    pose.pose.position.y = 0.0
    pose.pose.position.z = 0.3133
    pose.pose.orientation.x = 0.0
    pose.pose.orientation.y = 0.8633
    pose.pose.orientation.z = 0.0
    pose.pose.orientation.w = 0.5047
    arm.set_goal_state(pose_stamped_msg=pose, pose_link=TIP_LINK)
    plan_and_execute(robot, arm, logger, sleep_time=1.0)

    # --- 3) 충돌물체 추가 -> (충돌 인지) 계획 -> 제거 ---
    add_ground_box(robot, logger)
    arm.set_start_state_to_current_state()
    arm.set_goal_state(configuration_name="home")
    plan_and_execute(robot, arm, logger, sleep_time=1.0)
    remove_ground_box(robot, logger)

    # --- 4) 다중 파이프라인 계획 ---
    # 런치에서 각 파이프라인 이름의 plan_request_params 가 설정돼 있어야 동작.
    arm.set_start_state_to_current_state()
    arm.set_goal_state(configuration_name="home")
    try:
        multi = MultiPipelinePlanRequestParameters(
            robot, ["ompl_rrtc", "pilz_ptp"]
        )
        plan_and_execute(robot, arm, logger, multi_plan_parameters=multi,
                         sleep_time=1.0)
    except Exception as exc:  # 파이프라인 미설정 시 단일 계획으로 폴백
        logger.warn(f"다중 파이프라인 사용 불가({exc}) — 단일 계획으로 폴백")
        arm.set_start_state_to_current_state()
        arm.set_goal_state(configuration_name="home")
        plan_and_execute(robot, arm, logger, sleep_time=1.0)

    logger.info("예제 완료")
    # MoveItPy 는 파이썬 종료 시 소멸자에서 종종 segfault 를 낸다(알려진 이슈).
    # 작업은 위에서 모두 끝났으므로 소멸자를 타지 않고 즉시 정상 종료.
    os._exit(0)


if __name__ == "__main__":
    main()
