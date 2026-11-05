import bpy

# Find FBX export class
for cls in bpy.types.registered_classes:
    if 'FBX' in cls.bl_idname or 'fbx' in cls.bl_idname:
        print(f"Class: {cls.bl_idname}")
        for prop in cls.bl_rna.properties:
            if not prop.identifier.startswith('bl_'):
                print(f"  {prop.identifier}: {prop.type}")
