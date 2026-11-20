"""The Gaunt as it was before the redesign (old_gaunt.py, in this folder), posed mid-stalk, in the same three shots as the concepts, for comparison."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit
import old_gaunt as creature  # the Gaunt as shipped before the redesign (tools/blender/concepts/old_gaunt.py)


def build():
    ao, mesh = creature.assemble()
    rest = {b.name: b.matrix_local.to_3x3() for b in ao.data.bones}
    ao.animation_data_clear()
    creature.apply_pose(ao, creature.pose_stalk(0.2), rest)
    import bpy
    bpy.context.view_layer.update()
    return [ao]


if __name__ == "__main__":
    kit.main(build, "current")
