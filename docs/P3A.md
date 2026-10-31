# Phase 3A — ไอเท็ม กระเป๋า Hotbar และการเก็บทรัพยากร

เล่นได้แล้ว: ตัดต้นไม้ได้ไม้ ทุบหินได้หิน เก็บเห็ด ผลเบอร์รี่ และดอกไม้ป่า ของตกพื้นแล้วลอยเข้ากระเป๋า มี Hotbar 8 ช่อง และหน้ากระเป๋า 24 ช่อง

## 1. วิธีเล่น

| ปุ่ม | ทำอะไร |
|---|---|
| 1–8 หรือคลิกช่อง | เลือกช่อง Hotbar |
| คลิกซ้าย / F | ใช้เครื่องมือที่ถืออยู่กับต้นไม้/หินด้านหน้า (ขวานตัดต้นไม้ อีเต้อทุบหิน) |
| E | เก็บของด้วยมือ (พุ่มเบอร์รี่ เห็ด ดอกไม้ป่าในทุ่งหญ้า) |
| Tab / I | เปิด-ปิดกระเป๋า (ผู้เล่นหยุดเดินตอนเปิด) |
| ในกระเป๋า | คลิกช่อง = หยิบ (วงสีเขียว) → คลิกอีกช่อง = วาง (ของชนิดเดียวกันรวมกอง ต่างชนิดสลับกัน) · Shift-คลิก = ย้ายระหว่างแถว Hotbar กับกระเป๋า · Esc ปิด |

เริ่มเกมใหม่ได้ขวานกับอีเต้อ HUD แสดง "[Click] Chop Oak tree" เมื่อเครื่องมือเล็งเป้าหมายอยู่ และ "+4 Wood" มุมขวาล่างเมื่อได้ของ

## 2. ไอเท็ม (`resources/items/*.tres`)

| id | ชื่อ | ชนิด | กองสูงสุด | ได้จาก |
|---|---|---|---|---|
| `wood` | Wood | วัตถุดิบ | 99 | ต้นไม้ (2–5 ท่อน) |
| `stone` | Stone | วัตถุดิบ | 99 | หิน (เล็ก 1–2, ใหญ่ 3–5) |
| `mushroom` | Mushroom | ของป่า | 99 | กลุ่มเห็ดในป่า Westwood |
| `wild_berries` | Wild Berries | ของป่า | 99 | พุ่มเบอร์รี่ (ป่า หุบเขา ริมน้ำ) |
| `wildflower` | Wildflower | ของป่า | 99 | ดอกไม้สีเหลืองในทุ่งหญ้า |
| `axe` | Axe | เครื่องมือ | 1 | เริ่มเกม |
| `pickaxe` | Pickaxe | เครื่องมือ | 1 | เริ่มเกม |

`ItemData` (Resource): `id` (ห้ามเปลี่ยนเมื่อมีเซฟ), `display_name`, `description`, `category`, `icon` (SVG ใน `assets/ui/icons`), `world_art` (ภาพของตกพื้นใน `assets/art`), `max_stack`, `tool_type`, `sell_price`
เพิ่มไอเท็มใหม่: สร้าง `.tres` ใน `resources/items/` ชื่อไฟล์ = id (`ItemRegistry` โหลดเองทั้งโฟลเดอร์)

## 3. ตัด ทุบ เก็บ

| เป้าหมาย | ตีกี่ครั้ง | ได้ | งอกใหม่ |
|---|---|---|---|
| สน / ส้ม แอปเปิล มะนาว | 4 | ไม้ 2–4 | 900 วินาที |
| สนสูง / โอ๊ก | 5 | ไม้ 4–5 | 900 วินาที |
| หินเล็ก | 2 | หิน 1–2 | 1200 วินาที |
| หินใหญ่ | 4 | หิน 3–5 | 1200 วินาที |
| เห็ด เบอร์รี่ ดอกไม้ | กด E | 1 | 600 วินาที |

- ต้นไม้ที่ล้มกลายเป็นตอ เดินผ่านได้ หินที่แตกหายไป พุ่มเบอร์รี่ที่เก็บแล้วเหลือแต่ใบ
- ทุกต้น/ก้อน/จุดมี **ID ถาวร** (`nature:<tile x>_<tile y>`, `forage:<tile x>_<tile y>`) และสิ่งที่เก็บแล้วถูกจดใน `WorldState` — พร้อมให้ SaveManager (Phase 6) บันทึก
- เวลางอกใหม่นับเป็นวินาทีของเวลาเล่นไปก่อน จะเปลี่ยนเป็น "วัน" เมื่อมีระบบเวลาใน Phase 6 จะไม่งอกขณะผู้เล่นยืนอยู่ใกล้ (3 tile)
- ของที่ตกพื้นกระเด้งออกมา แล้วลอยเข้าหาผู้เล่นเมื่อเข้าใกล้ ~1.5 tile ถ้ากระเป๋าเต็มจะรออยู่บนพื้น

## 4. ไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `scripts/items/item_data.gd` · `item_registry.gd` (autoload `ItemRegistry`) | นิยามไอเท็ม และค้นหาตาม id |
| `scripts/inventory/inventory.gd` | `Inventory` (Node): ช่อง, เพิ่ม/ลด/ย้าย/รวมกอง, ช่องที่เลือก, `to_dict`/`from_dict` |
| `scripts/managers/world_state.gd` (autoload `WorldState`) | สิ่งที่เก็บไปแล้วกับเวลางอกใหม่ |
| `scripts/player/tool_user.gd` | `ToolUser`: ปุ่ม 1–8, ใช้เครื่องมือ, หาเป้าหมายด้านหน้า |
| `scripts/gathering/harvest_system.gd` | `HarvestSystem`: ตี/ล้ม/แตก, ของตก, งอกใหม่ |
| `scripts/gathering/item_pickup.gd` | `ItemPickup`: ของบนพื้น |
| `scripts/gathering/forage_spot.gd` | `ForageSpot` (Interactable): จุดเก็บด้วยมือ |
| `scripts/world/world_objects.gd` | เพิ่ม: ทะเบียนต้นไม้/หิน, ตาราง lookup, ตอไม้, จุด forage |
| `scripts/ui/item_slot_view.gd` · `hotbar.gd` · `inventory_panel.gd` | ช่องกลม, Hotbar, หน้ากระเป๋า |
| `scripts/ui/hud.gd` | สร้าง Hotbar/กระเป๋า/ข้อความรับของ, คำสั่ง [E] กับ [Click] |
| `tools/art/iso_art.py` | เพิ่มภาพ: ตอไม้ 2, พุ่มใบ, กลุ่มเห็ด, ของบนพื้น 7 |
| `tests/p3a_test.tscn` | ทดสอบ 35 ข้อ |

## 5. โครงสร้างฉาก (ส่วนที่เพิ่ม)
```
World
├─ Sim
│  ├─ Forage (Node2D)                 ForageSpot × ~1,000
│  └─ Player
│     ├─ Inventory (starting_items: axe 1, pickaxe 1)
│     └─ ToolUser
├─ View/Objects                       + ItemPickup (ของตกพื้น)
├─ HarvestSystem (objects → View/Objects, pickup_parent → View/Objects)
└─ HUD/Root                           + HotbarStrip/Hotbar, Toasts, InventoryPanel (สร้างในโค้ด)
```

## 6. Inspector

- **Inventory** — Size 24 · Hotbar Size 8 · Starting Items {axe: 1, pickaxe: 1}
- **ToolUser** — Swing Cooldown 0.4 วิ · Reach Forward 9 px · Reach Radius 10 px (แผนที่ 16 px/tile)
- **HarvestSystem** — Tree / Rock / Forage Regrow Seconds 900 / 1200 / 600 · Regrow Clear Distance 48 px
- **ItemPickup** — Attract Radius 26 px · Collect Radius 3 px · Fly Speed 70 px/วิ

## 7. Signal

| Signal | ส่งจาก | ฟังโดย |
|---|---|---|
| `Inventory.changed(slot)` / `selection_changed(slot)` | Inventory | Hotbar, InventoryPanel |
| `Inventory.item_added(item, count)` | Inventory | HUD (ข้อความ "+n") |
| `EventBus.tool_target_changed(prompt)` | ToolUser | HUD ("[Click] …") |
| `HarvestSystem.hit_landed(id, kind, hits_left)` | HarvestSystem | (เสียง/เอฟเฟกต์ภายหลัง) |
| `WorldState.harvest_changed(id, harvested)` | WorldState | (SaveManager ภายหลัง) |

## 8. ทดสอบ

```
godot --headless --path . res://tests/p3a_test.tscn
```
ผล **35/35**: โหลดไอเท็ม 7 ชนิด · มีไอคอนและภาพครบ · กฎกระเป๋า (รวมกอง ล้น เครื่องมือไม่ซ้อน ลบจากกองท้าย ไม่พอไม่ลบ สลับ รวม บันทึก/โหลด) · เริ่มด้วยขวาน+อีเต้อ · Hotbar 8 ช่อง · ปุ่ม 2 เลือกช่อง 2 · เล็งต้นไม้ · สนล้มใน 4 ครั้ง · กลายเป็นตอ · ตอไม่ขวาง · จดใน WorldState · ไม้ตกพื้น · ไม้ลอยเข้ากระเป๋า · ขวานไม่เล็งหิน · อีเต้อเล็งหิน · หินแตกได้หิน · หินหายไป · มือเปล่าไม่ตี · มีเห็ดในป่า ≥ 30 · เก็บเบอร์รี่/ดอกไม้ได้ · E เก็บเห็ด · เห็ดหาย · ต้นไม้งอกใหม่ · เห็ดงอกใหม่ · Tab เปิดกระเป๋า · คลิก-คลิกย้ายของ · Tab ปิดและเดินได้ · กระเป๋าเต็มของรอบนพื้น
และ `tests/p1_2d_test.tscn` ยังผ่าน 34/34

## 9. ข้อจำกัด
- ยังไม่มีเสียงและเอฟเฟกต์เศษไม้ (Phase 7) — ตอนตีต้นไม้สั่น ตัวละครเอนตัว
- ตัวละครยังไม่ถือเครื่องมือในมือ (ต้องวาดท่าฟันขวานเพิ่ม)
- ทิ้งของออกจากกระเป๋ายังไม่ได้ ของป่ายังกินไม่ได้ (รอระบบพลังงาน)
- เวลางอกใหม่เป็นวินาทีจริง ยังไม่ใช่วันในเกม
