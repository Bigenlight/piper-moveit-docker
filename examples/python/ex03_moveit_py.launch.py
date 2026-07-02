"""예제 3/3 전용 런치 — MoveItPy(in-process move_group) 단독 실행.

주의: run-mock.sh(demo.launch.py)와 동시에 띄우면 move_group 이 둘이 되어 충돌한다.
이 런치는 스스로 mock ros2_control + 컨트롤러 + robot_state_publisher 를 올리고,
마지막에 ex03_moveit_py_official.py 를 moveit_py 노드로 실행한다.

실행:
  source /opt/ros/jazzy/setup.bash
  source ~/piper-rwh/ros2_ws/install/setup.bash
  LC_NUMERIC=C ros2 launch ~/piper-rwh/examples/python/ex03_moveit_py.launch.py

리포의 demo.launch.py / _moveit_config_builder.py 구성을 그대로 따르되,
moveit_py 가 별도 move_group 을 띄우므로 move_group 노드는 뺐다.
RViz 는 팔 움직임을 보려면 켤 수 있다(use_rviz, 기본 true / 헤드리스는 use_rviz:=false):
  ... ros2 launch ~/piper-rwh/examples/python/ex03_moveit_py.launch.py use_rviz:=false
RViz 가 뜬 뒤 모션을 보도록 moveit_py 시작을 잠깐 지연시킨다(START_DELAY).
"""

from pathlib import Path

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, TimerAction
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from moveit_configs_utils import MoveItConfigsBuilder

# piper + agx_gripper 조합(리포 기본 프로파일)
XACRO_MAPPINGS = {
    "arm_type": "piper",
    "effector_type": "agx_gripper",
    "revo2_type": "left",
    "tcp_offset_xyz": "0.0 0.0 0.0",
    "tcp_offset_rpy": "0.0 0.0 0.0",
}
SRDF_MAPPINGS = {
    "arm_type": "piper",
    "effector_type": "agx_gripper",
    "revo2_type": "left",
}

# 이 디렉터리의 스크립트를 moveit_py 노드로 실행
THIS_DIR = Path(__file__).resolve().parent
SCRIPT = str(THIS_DIR / "ex03_moveit_py_official.py")
RVIZ_CONFIG = str(THIS_DIR / "ex03_moveit_py.rviz")

# RViz/컨트롤러가 뜬 뒤 모션을 보도록 moveit_py 노드 시작을 지연(초).
START_DELAY = 6.0

# MultiPipelinePlanRequestParameters 가 참조하는 파이프라인별 계획 파라미터.
# (이름 그룹 → 실제 로드된 파이프라인 매핑; 스크립트의 ["ompl_rrtc","pilz_ptp"]와 일치)
PLAN_REQUEST_PARAMS = {
    "plan_request_params": {
        "planning_attempts": 1,
        "planning_pipeline": "ompl",
        "planner_id": "RRTConnectkConfigDefault",
        "max_velocity_scaling_factor": 0.2,
        "max_acceleration_scaling_factor": 0.2,
    },
    "ompl_rrtc": {
        "plan_request_params": {
            "planning_attempts": 1,
            "planning_pipeline": "ompl",
            "planner_id": "RRTConnectkConfigDefault",
            "max_velocity_scaling_factor": 0.2,
            "max_acceleration_scaling_factor": 0.2,
        }
    },
    "pilz_ptp": {
        "plan_request_params": {
            "planning_attempts": 1,
            "planning_pipeline": "pilz_industrial_motion_planner",
            "planner_id": "PTP",
            "max_velocity_scaling_factor": 0.2,
            "max_acceleration_scaling_factor": 0.2,
        }
    },
}


def generate_launch_description():
    pkg = "agx_arm_moveit"

    moveit_config = (
        MoveItConfigsBuilder("agx_arm", package_name=pkg)
        .robot_description(
            file_path="config/agx_arm.urdf.xacro", mappings=XACRO_MAPPINGS
        )
        .robot_description_semantic(
            file_path="config/agx_arm.srdf.xacro", mappings=SRDF_MAPPINGS
        )
        .robot_description_kinematics(file_path="config/kinematics.yaml")
        .joint_limits(file_path="config/joint_limits.yaml")
        .trajectory_execution(file_path="config/moveit_controllers_gripper.yaml")
        .planning_pipelines(  # ompl + pilz(다중 파이프라인용) 명시 로드
            default_planning_pipeline="ompl",
            pipelines=["ompl", "pilz_industrial_motion_planner"],
        )
        .pilz_cartesian_limits(file_path="config/pilz_cartesian_limits.yaml")
        .to_moveit_configs()
    )

    # 리포에 이미 있는 ros2_control 컨트롤러 정의(arm/gripper/broadcaster)
    ros2_controllers = str(
        Path(get_package_share_directory(pkg)) / "config" / "ros2_controllers.yaml"
    )

    rsp = Node(
        package="robot_state_publisher",
        executable="robot_state_publisher",
        output="screen",
        parameters=[moveit_config.robot_description],
    )

    # mock 하드웨어 컨트롤러 매니저
    ros2_control_node = Node(
        package="controller_manager",
        executable="ros2_control_node",
        output="screen",
        parameters=[moveit_config.robot_description, ros2_controllers],
    )

    def spawner(name):
        return Node(
            package="controller_manager",
            executable="spawner",
            arguments=[name, "--controller-manager", "/controller_manager"],
            output="screen",
        )

    # --- MoveItPy(moveit_cpp) 파라미터 형식 보정 ---
    # to_dict() 의 planning_pipelines 는 move_group 용 '평탄 리스트'지만,
    # MoveItPy(moveit_cpp) 는 planning_pipelines.pipeline_names 중첩 형식을 요구한다.
    # (공식 튜토리얼의 moveit_cpp.yaml 이 채워주는 값을 여기서 직접 맞춘다.)
    moveit_py_params = moveit_config.to_dict()
    pipeline_names = moveit_py_params.pop("planning_pipelines", ["ompl"])
    moveit_py_params["planning_pipelines"] = {"pipeline_names": pipeline_names}
    # 3D 포인트클라우드 옥토맵 센서는 이 셋업에 불필요 -> 로드 에러 방지 위해 제거
    moveit_py_params.pop("sensors", None)
    moveit_py_params.pop("point_cloud_sensor", None)
    # 기본/파이프라인별 plan_request_params 주입
    moveit_py_params.update(PLAN_REQUEST_PARAMS)

    # MoveItPy 노드: 이름을 "moveit_py"로 맞춰 파라미터가 올바른 노드로 주입되게 함
    moveit_py_node = Node(
        name="moveit_py",
        executable=SCRIPT,  # shebang + 실행권한으로 직접 실행
        output="screen",
        parameters=[moveit_py_params],
    )
    # RViz 가 먼저 뜨고 컨트롤러가 active 된 뒤 모션이 보이도록 지연 시작
    delayed_moveit_py = TimerAction(period=START_DELAY, actions=[moveit_py_node])

    # 관전용 RViz (RobotModel+TF). use_rviz:=false 면 헤드리스.
    rviz_node = Node(
        package="rviz2",
        executable="rviz2",
        arguments=["-d", RVIZ_CONFIG],
        output="screen",
        parameters=[moveit_config.robot_description],
        condition=IfCondition(LaunchConfiguration("use_rviz")),
    )

    return LaunchDescription([
        DeclareLaunchArgument(
            "use_rviz",
            default_value="true",
            choices=["true", "false"],
            description="팔 움직임을 볼 RViz 를 띄운다(기본 true). 헤드리스면 false.",
        ),
        rsp,
        ros2_control_node,
        spawner("joint_state_broadcaster"),
        spawner("arm_controller"),
        spawner("gripper_controller"),
        rviz_node,
        delayed_moveit_py,
    ])
