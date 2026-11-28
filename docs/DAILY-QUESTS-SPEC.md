# Ежедневные задания — финальная спецификация

Обновлено: 27.11.2026. Реализация по волнам: сервер → клиент → UI.

## Константы

| Параметр | Значение |
|---|---|
| День | 04:00 МСК → 03:59 МСК, UTC+3 fixed |
| Заданий в день | 3 (active / steady / flex) |
| Замен | 1 бесплатная + 2 платных по 1 осколку = 3 |
| Награда E/M/H | 3/150, 4/200, 5/250 (осколки/XP) |
| Бонус | все 3 задания = +10 осколков, 1 раз в день |
| Неделя | Пн 04:00 → Вс 03:59, 7/7, день закрыт только когда выполнены **все 3** задания |
| Лестница | нед. 1 — товар 100; нед. 2 — 1000; нед. 3 — 3000; нед. 4 — скин 10–12; далее цикл 1000 → 3000 → скин |
| Компенсация | товар есть → 100; скин есть → 1000 (в т.ч. скин охотницы) |
| Боевой магазин | 2 и 3 покупки за бой; 3 — с 20+ матчей |
| Сезонный якорь | понедельник 2026-11-30 = неделя 1 |

## Волны и файлы

### Волна 1 — сервер
- A: `server/schema.sql`, `server/quests.go`, `server/quests_test.go`.
- B: `server/ws.go`, `server/main.go`, `server/ws_quests_test.go`.
- Контракт: `questDayKey`, `questResetsAt`, `questWeekStart`, `questSeasonTier`, `generateQuests`, `ensureDailyQuests`, `applyQuestProgress`, `buildDailySummary`, `handleQuests`, `handleQuestReroll`, `handleWeeklyClaim`.

### Волна 2 — клиент
- `scripts/daily_quests.gd` (autoload), `scripts/network_client.gd`, `scripts/MetaProgression.gd`, `project.godot`.

### Волна 3 — UI
- `scripts/daily_quests_panel.gd`, `scripts/lobby.gd`, `scripts/weapon_catalog.gd`, `tools/daily_quests_probe.gd`.

## Схема БД

```sql
CREATE TABLE IF NOT EXISTS daily_quest_days (
    player_id        BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    quest_day        DATE   NOT NULL,
    seed             BIGINT NOT NULL,
    reroll_seq       SMALLINT NOT NULL DEFAULT 0,
    free_reroll_used BOOLEAN  NOT NULL DEFAULT FALSE,
    paid_rerolls     SMALLINT NOT NULL DEFAULT 0,
    completed_count  SMALLINT NOT NULL DEFAULT 0,
    all_done_bonus   BOOLEAN  NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, quest_day)
);
CREATE INDEX IF NOT EXISTS daily_quest_days_day_idx ON daily_quest_days (quest_day);

CREATE TABLE IF NOT EXISTS daily_quests (
    player_id     BIGINT NOT NULL,
    quest_day     DATE   NOT NULL,
    slot          SMALLINT NOT NULL,
    template_id   TEXT NOT NULL,
    metric        TEXT NOT NULL,
    target        INTEGER NOT NULL,
    progress      INTEGER NOT NULL DEFAULT 0,
    reward_shards SMALLINT NOT NULL,
    reward_xp     SMALLINT NOT NULL,
    rerolled      BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at  TIMESTAMPTZ,
    PRIMARY KEY (player_id, quest_day, slot),
    FOREIGN KEY (player_id, quest_day)
        REFERENCES daily_quest_days (player_id, quest_day) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS daily_quests_day_idx ON daily_quests (quest_day);

CREATE TABLE IF NOT EXISTS weekly_grants (
    player_id   BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    week_start  DATE   NOT NULL,
    tier        SMALLINT NOT NULL,
    reward_kind TEXT NOT NULL,
    item_id     INTEGER NOT NULL DEFAULT 0,
    shards      INTEGER NOT NULL DEFAULT 0,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, week_start)
);
```

`matches`: добавить `duration_sec`, `kills`, `deaths`, `damage`, `crystals`, `shells`, `shop_items` (INTEGER NOT NULL DEFAULT 0), `class_key` (TEXT NOT NULL DEFAULT ''). Только `ADD COLUMN IF NOT EXISTS`. Уникальный индекс `(room_id, player_id)` в этой волне не добавлять — сначала проверить дубли.

## API

- `GET /profile`: добавить `daily: {completed,total,resets_at,week:{active_days,required,tier,claimable,claimed}}`.
- `GET /quests?player_id=...`: 3 задания, `rerolls`, `today`, `week` (7 дней, tier, reward, missed, previous).
- `POST /quests/reroll`: `{player_id,day,slot,current_template_id}`; free → paid 1 осколок → 409.
- `POST /quests/weekly_claim`: `{player_id,week_start,item_id}`; 7/7, идемпотентно.
- Ошибки: 400/401/402/404/409/500; `Cache-Control: no-store`.

## Шаблоны MVP (16)

| id | title | metric | target | diff | награда | min матчей |
|---|---|---|---:|---|---|---:|
| kills_8 | Убить 8 врагов | kills | 8 | E | 3/150 | 0 |
| kills_12 | Убить 12 врагов | kills | 12 | M | 4/200 | 5 |
| triple_kill | 3 убийства за бой | max_kills_one | 3 | M | 4/200 | 3 |
| damage_4000 | Нанести урон 4000 | damage | 4000 | M | 4/200 | 0 |
| damage_7000 | Нанести урон 7000 | damage | 7000 | H | 5/250 | 10 |
| shells_2 | Разрушить 2 снаряда | shells | 2 | E | 3/150 | 0 |
| crystal_2 | Доставить 2 кристалла | crystals | 2 | M | 4/200 | 0 |
| crystal_3 | Доставить 3 кристалла | crystals | 3 | H | 5/250 | 5 |
| play_2 | Сыграть 2 боя | matches | 2 | E | 3/150 | 0 |
| play_3 | Сыграть 3 боя | matches | 3 | E | 3/150 | 0 |
| win_1 | Победить | wins | 1 | E | 3/150 | 0 |
| win_2 | Победить 2 раза | wins | 2 | M | 4/200 | 3 |
| fast_win | Победа за 7 мин | fast_wins | 1 | M | 4/200 | 3 |
| fast_win_2 | 2 быстрые победы | fast_wins | 2 | H | 5/250 | 10 |
| buy_2 | Купить 2 усиления | shop_items_one | 2 | M | 4/200 | 0 |
| buy_3 | Купить 3 усиления | shop_items_one | 3 | H | 5/250 | 20 |

Позже: `survive_win`, heal/stun/2 classes.

## Генерация и прогресс

- Сид `fnv1a64("dq|"+pid+"|"+day)`, SplitMix64, `rerollSeq` сдвигает поток.
- 3 разных template_id, разные категории, ровно 1 easy, ≤1 win, сумма ~15–25 минут.
- Новичкам (<10 матчей) недоступны triple_kill, fast_win_2, survive_win, buy_3.
- Прогресс только из валидированного `saveMatch`, матч короче 90 с игнорируется.
- Для kills/damage/crystals/shells — прогресс добавляет весь результат матча (не больше цели).
- `shop_items` = `len(client.bought)` на финише; `buy_2` — max за один бой.
- При завершении: `completed_at`, `completed_count++`, шарды, XP; все 3 → +10.
- Замена: `FOR UPDATE`, completed нельзя, `current_template_id` защищает от двойного тапа; free → paid 1 осколок (max 2 paid).
- День закрыт только при `completed_count = 3` (все задания).
- Неделя: `active_days = COUNT(completed_count = 3)`, claimable при 7/7, окно текущая+предыдущая, `weekly_grants` PK.

## UI

### Desktop 1440×734
- Таблица на месте плашки: left 28.8, top 122.4, width 327.
- Заголовок 48 px, строка 42 px (текст 18, мета 16, бар 4), неделя+скин 40 px.
- Высоты: 0 → 48, 1 → 154, 2 → 200, 3 → 246; tween 0.18 s.
- Пустое состояние — только заголовок.

### Mobile 844×390
- Жёлтая кнопка «ЗАДАНИЯ» 235×48 в инвентаре сразу под `menu_level_label`, бейдж `0/3`.
- Оверлей full-rect, z=42; панель 812 px; высоты 338/286/234/136.
- Шрифты 20/18/18/18; закрытие ×, тап вне, Esc; `_close_player_menu` скрывает оверлей.
- Возврат сохраняет скролл инвентаря.

## Тесты

- Go unit: границы дня, детерминизм, ограничения, новички, reroll free/paid/limit, completed, no shards, идемпотентность, полный прогресс за матч, min duration, shop_2, бонус, 7/7, пропуск, tier, claim идемпотентность, компенсации.
- Интеграция: матч → counters → прогресс → награды, повторный финиш не платит.
- GDScript: `DailyQuestsLayoutProbe` 1440/844, `DailyQuestsStateProbe`; регресс `NonCombatUiProbe`, `ResultsProbe`, `ShopSkinProbe`, `TutorialLayoutProbe`.

## Риски

1. Строгие 7/7 + 1 бесплатная замена: гарантировать `play_2` в лёгком слоте, ≤1 win.
2. Лестница после 4-й недели: повтор 1000 → 3000 → скин; следить за инфляцией, компенсация скина 1000.
3. Счётчики в `ws.go`: только инкременты в существующих ветках, не менять формулы урона/HP; `HpDesyncProbe`/`ScoreboardProbe` после.
