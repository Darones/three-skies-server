# Blender MCP test script v2
# Creates a cube, assigns blue material, renders viewport

import bpy
import os

# Clear existing objects (keep only camera)
bpy.ops.object.select_all(action='DESELECT')
for obj in list(bpy.data.objects):
    if obj.type != 'CAMERA':
        bpy.data.objects.remove(obj, do_unlink=True)

# Remove old materials
for mat in list(bpy.data.materials):
    bpy.data.materials.remove(mat)

# Create cube
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 0))
cube = bpy.context.active_object
cube.name = "TestCube"

# Create blue material with nodes
mat = bpy.data.materials.new(name="BlueMaterial")
mat.use_nodes = True
nodes = mat.node_tree.nodes
links = mat.node_tree.links

# Clear default nodes
nodes.clear()

# Add output node
output_node = nodes.new(type='ShaderNodeOutputMaterial')
output_node.location = (400, 0)

# Add Principled BSDF node
bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
bsdf.location = (0, 0)
bsdf.inputs['Base Color'].default_value = (0.0, 0.0, 1.0, 1.0)  # RGB 0,0,1
bsdf.inputs['Roughness'].default_value = 0.5

# Link BSDF to output
links.new(bsdf.outputs['BSDF'], output_node.inputs['Surface'])

# Assign material to cube
if cube.data.materials:
    cube.data.materials[0] = mat
else:
    cube.data.materials.append(mat)

# Setup scene for rendering (Blender 5.2 API)
scene = bpy.context.scene
scene.render.filepath = os.path.join(os.path.dirname(__file__), "blender_mcp_test_output.png")
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'

# Setup camera
cam_data = bpy.data.cameras.new(name="TestCamera")
cam_obj = bpy.data.objects.new("TestCamera", cam_data)
scene.collection.objects.link(cam_obj)
cam_obj.location = (4, -4, 4)
rot = cam_obj.rotation_euler
rot.x = 0.7854  # ~45 degrees
rot.z = 0.7854
scene.camera = cam_obj

# Render
bpy.ops.render.render(write_still=True)
print("RENDER_DONE")
print("Object: " + cube.name)
print("Material: " + mat.name)
print("Color: RGB(0.0, 0.0, 1.0)")
print("Roughness: 0.5")
print("Output: " + scene.render.filepath)
