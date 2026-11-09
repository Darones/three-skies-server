# Навык: Безопасная работа с VFX в Godot 4
1. НИКОГДА не применяй свойства (emission, light_energy) к корневому узлу (Node3D). 
2. Всегда проверяй тип узла: `if node is GeometryInstance3D:` или `if node is Light3D:`.
3. Для поиска нужных узлов используй `find_children("*", "GeometryInstance3D", true, false)`.
4. Обязательно добавляй проверку на null: `if not node: return`.
5. Удаляй эффекты через `queue_free()` с таймером (например, `await get_tree().create_timer(1.5).timeout`).