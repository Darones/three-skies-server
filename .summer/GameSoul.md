# Осколки Неба

## Current Visual Update

- The shared runtime wing attachment stays at zero rotation on X; the wing model uses Y=18 degrees and Z=10 degrees for Warrior, Mage, and Fairy. Its BaseMaterial3D surfaces are duplicated with culling disabled so both sides render.
- Binbun VFX in `scripts/hero.gd` use a 1.6 scale / +0.6 m / 1.6 emission / 2.0 light default; class auto-attacks use 1.2 scale, abilities 1/2 use 1.15/1.5, ultimates use 2.0 scale and light energy 3.0. Warrior routes to hit_01, hit_02, impact_01, big_impact_01; Mage to hit_02, hit_01, impact_02, impact_01; Fairy to hit_02, hit_01, impact_01, impact_02 (auto, abilities 1/2, ultimate). Effects are class-tinted and cleaned up after their clip with a 0.6 s minimum.
- The shared `CPUParticles3D` burst pool now uses a procedural soft radial alpha texture, additive billboard shading, a fade-in/out color ramp, and 1.35 emission energy. Pool sizes remain bounded from 3 to 60 particles per burst with a 0.6 s particle lifetime; hit VFX scenes keep their authored textured shaders and curves.
- The loading scene is a 15-second matchmaking screen with a background image, pulsing logo, six team slots, simulated balanced player arrivals, bot fillers, slot-count progress, rotating gameplay tips and threaded loading of Main.tscn.
- Lobby actions are anchored symmetrically at the bottom corners: Play on the right and settings on the left, each 45 px from the edges.
- Lobby player name/level and shard balance labels match the 27 px central hero-name size.
- The two arena floor materials use triplanar texture mapping at 0.12 scale to avoid stretching across the expanded floor.
- The warm-sky/light-fog lighting experiment was rolled back; the arena keeps its prior near-black background and depth fog (10–55), cool blue-white sun (energy 0.95), and blue-gray ambient fill (energy 0.75). The triplanar floor update remains.
- Runtime class weapons attach to humanoid hand bones: Warrior sword on RightHand at scale 0.72, Mage staff on RightHand at 0.62, and Fairy bow on LeftHand at 0.9. Weapon attack clips are `swing` for Warrior/Mage and `shoot` for Fairy. Weapon effects are additive overlays only: a cyan staff tip orb/halo with 12 CPU sparks and a small no-shadow light; a gold sword tip/hilt glow, two blade strips/sheens, 12 gold sparks and a small light; and a subtle green bow glow with 7 sparks. Effects use 30 Hz CPU particles, fade by 18 m, and do not cast shadows.
- Soundza SFX are wired with max-polyphony limits: persistent lobby UI clicks use `menu_selection_click`; Warrior uses randomized sword swings and impact sounds plus an explosion for the fear ultimate, Mage uses magic casts, and Fairy uses airy bow whooshes. Fountain coins, successful shop purchases, shard pickup/delivery, and victory/defeat use pickup and jingle stingers.

- Optimized light-side tree assets remain imported, but tree instances and their visibility occluders are no longer placed in the match arena.
- Godot's built-in import LODs were measured at 249,998, 124,996, 62,498, and 36,728 triangles from a 500,000-triangle base mesh. The base mesh was not reduced to 5–10k.
- Arena bushes use `small_stylised_bush.glb`, doubled to 4.3 m and placed in pairs at the original eight stealth zones. Two MultiMesh batches render the 16 bushes; Area3D triggers and collision shapes remain unchanged.
- Floor tiles now share continuous vertex heights and normals, removing the visible mesh grid seams; slate vein contrast is reduced.
- Decorative trees, loose rocks and visible perimeter boulders remain removed. Eight crystal clusters and eight paired stylized-bush stealth zones are placed across the arena. The five braziers, tactical ruin blocks, and perimeter collision remain.
- The radial translucent `FloatingClouds/CloudWall` and the altar's two glowing rings are removed; the shard pedestal remains. Match fog-of-war is restored as a soft ground overlay, with 10-meter team vision and obstacle-aware enemy visibility. A fully opaque black annulus still hides cut terrain beyond the island.

## Vision
Три игрока против трёх на обломках небесного храма, висящего над пропастью. Каждый матч длится пять минут, цель одна: разбить охранника-Оболочку, подобрать кристалл и дотащить его на базу раньше, чем это сделает враг. Простая задача, но носитель кристалла замедлен, Оболочка бьёт молниями, а противник уже бежит с другого фланга.

Игра про чёткие решения в сжатое время. Иди к кристаллу сейчас или защищай того, кто уже несёт. Воин врывается и оглушает, Маг держит щит и лечит, Фея выбивает противника на расстоянии. Когда трое делают это одновременно и слаженно, всё складывается в одно движение. Когда нет, кристалл роняют посреди карты, и начинается хаос.

## Genre and Style

- **Type**: тактическая арена 3 на 3, PvP с чёткими классами, матчи до шести минут, мобильное и веб-управление.
- **Inspirations**: Warcraft III дал стилизованных героев с читаемыми ролями и тёмное фэнтезийное ощущение мира; Battlerite дал ритм коротких столкновений без фарма и лишней беготни; Dota 2 дал глубину синергии между классами и визуальную чёткость скиллов.
- **What makes it theirs**: кристалл как движущаяся цель. Не башня, не точка захвата, а предмет, который нужно нести, пока тебя замедляет и преследуют. Это сдвигает акцент с «убей всех» на «донеси живым».

## Look and Feel

- Typography: Philosopher Regular is the project-wide UI and 3D-label font; Philosopher Bold is available for emphasized text.

- **Art style**: стилизованный low-poly 3D, изометрия под 45°. Пропорции героев слегка утрированы. Светлая сторона карты: золотые доспехи, белые ткани, солнечные лучи сквозь листву. Тёмная сторона: обсидиан, фиолетовые кристаллы, туман. Камень и металл с физически корректными материалами, но без фотореализма. Цветовая палитра: тёмный сланец и древесный уголь как основа, насыщенные ювелирные акценты на магии и эффектах.
- Небо — процедурный градиент от глубокого синего к бирюзовому; край острова закрывает невысокая каменная гряда, за которой весь обрыв уходит в сплошной чёрный фон.
- **Mood and sound**: в спокойные моменты, когда кристалл ещё не появился, звучит тревожное низкое гудение. В момент появления Оболочки темп резко вырастает: тяжёлые виолончели, редкие удары больших барабанов, мрачные хоровые распевы. Ритм всегда чёткий, музыка не усыпляет даже между схватками.
- Ульта Воина сопровождается кратким землетрясением с трещинами на земле; ульта Феи — золотыми кольцами, частицами и бесплатным звуковым эффектом колокольчиков.
- На обеих базах действует защита от урона с полупрозрачным куполом цвета команды; декоративные кристаллы стоят вне кустовых зон, а осколок при падении выбирает свободное место.

## The Hero, the World, the Moment

На прямых подходах от обеих баз к центру лежат поперёк пути упавшие колонны; центральный проход перекрыт, обход открыт с боков.

Компактная миникарта размером 160×110 расположена внизу по центру; собственная база всегда снизу, союзники зелёные, видимые противники красные, магазин и фонтан обозначены золотыми значками, а носитель Осколка выделен золотым кольцом.

Три класса, одна команда. Воин идёт вперёд и держит удар, Маг держит команду живой и контролирует пространство лозами, Фея работает с дистанции и выбивает цели оглушением. Новичок не умирает мгновенно: персонажи живучие, респавн короткий, урон Оболочки терпимый.

Руины небесного храма на парящих островах. Три пути между базами. Светлая половина цветёт, тёмная скручена и затянута туманом. В центре, на открытой площадке с алтарём, появляется Оболочка. Деревья и колонны блокируют физические снаряды и взгляд, но не магию.

Оболочка появляется, подсветка за десять секунд предупреждает обе команды. Нужно добраться первым, бить её вместе, подобрать кристалл и нести к базе, пока противник пытается тебя остановить. Это главный момент каждого матча.

## Core Mechanics

Игрок движется левым стиком, направление атаки совпадает с направлением стика. Правая сторона экрана: четыре кнопки скиллов с кулдаунами. Прицелов нет, скиллы летят по направлению стика или наводятся автоматически на ближайшего. Кристалл появляется каждые 90 секунд на одном из двух флангов. Оболочку нужно уничтожить за 45 секунд. Носитель кристалла замедлен вдвое. Первая команда с тремя кристаллами на базе побеждает. При ничьей по таймеру побеждает команда с бо́льшим счётом. Если счёт равный, следующий кристалл решает. Боты заполняют пустые слоты. *Допущение: время респавна 8 секунд.*

## First Playable Version

Одна карта, центральная площадка с алтарём. Три класса против трёх ботов. Одна Оболочка, один кристалл, одна база. Скиллы работают, кристалл можно подобрать и донести. Победа и поражение засчитываются. Музыка и звуки схватки присутствуют.

## Open Questions

## Current Implementation Update

- The loading-screen logo is static; its idle float and scale pulse are removed.
- Arena foliage and leaf-tip meshes are enlarged in both the saved main scene and the arena generator; stealth collision volumes are unchanged.
- The shard shop keeps the cheapest wing item and adds text-only staff, bow, and sword placeholders. The inventory shows Legendary sword, staff, and bow slots instead of wings.
- Team 0's Light base is at Z=28 and team 1's Dark base is at Z=-28 in the current arena. Spawns, bot return targets, base checks, and shard delivery match those altar positions.
- Respawns use the base center with a small lateral spread on the platform; shard carriers retain their separate, slightly inset approach target.
- The Sky Shard uses `assets/models/detail-crystal.glb`, scaled to about 1.15 m tall with cyan emission; pickup and carry logic remain attached to the original `Crystal` root node. A neutral colormap fills the GLB's missing external texture URI.
- Ruin blocks and columns plus all eight crystal clusters now have static collisions. The arena NavMesh is baked from static colliders with a 0.6 m agent radius and a carved center around the Shell spawn; bots approach the Shell on a class-range ring instead of pathing into its center.

Сколько секунд длится респавн по умолчанию?
Как именно работает эволюция класса на 10 уровне: меняется только визуал и пассивка, или открываются новые ульты?
Кусты дают полную невидимость или только прерывают прицел?
Что видит игрок, пока он мёртв: камера союзника или статичный вид сверху?

- The visual floor mesh at Arena/Island/Floor is 230x200 world units with its original slate texture and UV scale compensated. The 104x74 world collision remains unchanged; Dark_Apron is removed. The 45-degree camera, near-black background/fog (end 55), and layer-0 vignette remain.
- The match HUD now opens a pause menu on Escape and on a mobile-only circular menu button beside the scoreboard. It offers resume, settings, and exit; web returns to the lobby because browsers cannot close themselves.
- Lobby and pause share a settings panel: master volume on all platforms, editable keyboard bindings on non-mobile platforms, and a vibration toggle on mobile. Settings persist in `user://game_settings.cfg`; enabled mobile vibration provides haptics on skill taps and when pausing.
- Both bases now show very subtle team-tinted, non-colliding spawn-protection domes, matching the existing 4.9-meter damage-immunity radius. The pause-menu exit returns to the lobby on all platforms.
- Lobby player-menu arrows switch among Warrior, Mage, and Fairy. Wing ownership stays shared, but equipped wings are saved per character; the shop only purchases wings, while each character's wardrobe can equip or remove them.
- Battle effects use the Binbun Stylized Hit FX pack: `vfx_hit_01` on melee and projectile hits, `vfx_big_impact_01` on the Warrior ultimate, blue-tinted `vfx_impact_01` on Mage lightning hits, and `vfx_impact_02` on Fairy golden-buff rings. Spawned effects play their `main` animation once, fill missing 3D hit audio streams from the existing SFX pack, then free themselves on completion. Selected scene resource paths point to the actual `assets/hit_fx/BinbunVFX_Vol2` folder.
