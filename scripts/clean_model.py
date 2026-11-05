import bpy
import sys
import os

# --- НАСТРОЙКИ ---
INPUT_PATH = r"C:\myGames3D\three-skies\assets\models\warrior.glb"
OUTPUT_PATH = r"C:\myGames3D\three-skies\assets\models\warrior_clean.fbx"

# --- 0. ВКЛЮЧАЕМ GLTF ADON ---
print("[0/5] Включение аддона glTF...")
bpy.ops.preferences.addon_enable(module="io_scene_gltf2")

# --- 1. ИМПОРТ ---
print(f"[1/5] Импорт: {INPUT_PATH}")
bpy.ops.import_scene.gltf(filepath=INPUT_PATH)

# --- 2. СОБИРАЕМ ВСЕ ОБЪЕКТЫ ---
all_objs = bpy.data.objects[:]
print(f"  Найдено объектов: {len(all_objs)}")

# --- 3. СОБИРАЕМ ТОЛЬКО МЕШИ ---
mesh_objects = []
for obj in all_objs:
    # Пропускаем камеры, источники света, пустышки, арматуры
    if obj.type == 'MESH':
        mesh_objects.append(obj)
    elif obj.type == 'EMPTY':
        print(f"  Удаление Empty: {obj.name}")
        bpy.data.objects.remove(obj, do_unlink=True)
    elif obj.type == 'ARMATURE':
        print(f"  Удаление Armature: {obj.name}")
        bpy.data.objects.remove(obj, do_unlink=True)
    elif obj.type in ('CAMERA', 'LIGHT'):
        # Оставляем камеры и свет — они не мешают риггингу
        print(f"  Оставляем: {obj.name} ({obj.type})")

print(f"  Осталось мешей: {len(mesh_objects)}")

if not mesh_objects:
    print("ОШИБКА: Мешей не найдено!")
    sys.exit(1)

# --- 4. ПРИМЕНЯЕМ ТРАНСФОРМЫ ---
print("[4/5] Применение трансформаций...")
for obj in mesh_objects:
    # Делаем объект активным
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    print(f"    Применено: {obj.name}")

# --- 5. ЭКСПОРТ В FBX ---
print(f"[5/5] Экспорт в: {OUTPUT_PATH}")

# Убедимся, что в сцене только меш-объекты
bpy.ops.object.select_all(action='DESELECT')
for obj in mesh_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = mesh_objects[0]

bpy.ops.export_scene.fbx(
    filepath=OUTPUT_PATH,
    add_leaf_bones=False,
    use_subsurf=False,
    use_mesh_modifiers=True,
    use_mesh_edges=False,
    global_scale=1.0,
    object_types={'MESH'},
    use_anim=False,
    bake_space_transform=True,
)

print(f"ГОТОВО: {OUTPUT_PATH}")
print(f"Мешей экспортировано: {len(mesh_objects)}")
