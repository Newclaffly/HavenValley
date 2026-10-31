# Phase 1 — รากฐาน (Foundation)

สถานะ: **เสร็จ รอทดสอบบน Windows และอนุมัติ** · ทดสอบด้วย Godot 4.7.2 แล้ว: ฉากทดสอบอัตโนมัติผ่าน 27/27 ข้อ ไม่มี error หรือ warning

## 1. ออกแบบ (Design)

เป้าหมายของเฟสนี้คือ "โครงที่เดินได้": เปิดเกม → เมนูหลัก → New Game → เกิดในฟาร์ม → เดินสำรวจโลก greybox ขนาด 1 × 1 กม. ตามแบบแปลน → กด E อ่านป้าย → ESC หยุดเกม

| ปุ่ม | การทำงาน |
|---|---|
| W A S D / ลูกศร | เดิน (ตามทิศที่กล้องมอง) |
| Shift | วิ่ง |
| Space | กระโดด |
| เมาส์ | หมุนกล้อง · ล้อเมาส์ซูม 2–8 ม. · คลิกซ้ายเพื่อจับเมาส์กลับเข้าเกม |
| E | โต้ตอบ (อ่านป้าย) |
| ESC | หยุดเกม / เล่นต่อ |
| F3 | แสดง/ซ่อนข้อมูลดีบัก (FPS, พิกัด, chunk, ความเร็ว) |

ปุ่มทั้งหมดผูกกับ **physical key** (ตำแหน่งปุ่ม) จึงใช้ได้แม้เปิดคีย์บอร์ดภาษาไทยอยู่

ค่าตัวเลข: เดิน 4 ม./วิ · วิ่ง 7 ม./วิ · กระโดดสูง 1.2 ม. · ผู้เล่นสูง 1.75 ม. · ไต่ทางลาดได้สูงสุด 40°

## 2. สถาปัตยกรรม (Architecture)

```
Autoloads (มีแค่ 2 ตัว ตามกฎ "อย่าทำทุกระบบเป็น Autoload")
  EventBus     ศูนย์กลาง signal: ระบบเกมส่ง → UI ฟัง ไม่ต้องอ้างอิงกันตรงๆ
  GameManager  สถานะเกม (MAIN_MENU / PLAYING / PAUSED), เปลี่ยนฉาก, หยุดเกม, โหมดเมาส์

ฉาก (Scene)
  main_menu.tscn  →  GameManager.start_new_game()  →  world.tscn
  world.tscn
    WorldManager    (สคริปต์ของฉาก ไม่ใช่ autoload) วางผู้เล่นที่จุดเกิด ติดตาม chunk
    GreyboxBuilder  สร้างโลกทั้งหมดจาก world_layout.json ตอนเริ่มเกม
    Player          PlayerController + PlayerCameraRig + InteractionDetector
    HUD             ฟัง EventBus อย่างเดียว
    PauseMenu       ฟัง EventBus.game_paused

ข้อมูล
  resources/world/world_layout.json  ← แหล่งพิกัดเดียวของทั้งโปรเจกต์ (มาจาก blueprint v0.2)
```

การตัดสินใจทางเทคนิค
- **โลก greybox สร้างจาก JSON ตอนรันไทม์** แทนการวางกล่องเองในฉาก ถ้าแก้พิกัดใน JSON โลกในเกมเปลี่ยนตามทันที ไม่มีทางคลาดกับแบบแปลน ใน editor กดปุ่ม **Rebuild Preview** ที่โหนด Greybox เพื่อดูตัวอย่าง (ตัวอย่างไม่ถูกบันทึกลงฉาก)
- **Greybox แบนที่ Y = 0** ค่า Y ในแบบแปลนถูกข้ามไปก่อน ความสูงจริงมากับภูมิประเทศใน Phase 2
- **Physics interpolation เปิดอยู่** ฟิสิกส์ทำงาน 60 Hz แต่ภาพลื่นทุก refresh rate กล้องเป็น `top_level` และตามตำแหน่งแบบ interpolate ของผู้เล่นทุกเฟรม
- **กล้องไม่ทะลุกำแพง** ใช้ `SpringArm3D` (ทรงกลมรัศมี 0.25 ม.) ชนกับเลเยอร์ world และไม่ชนตัวผู้เล่นเอง
- **การเคลื่อนที่อิงทิศกล้องแนวนอน (yaw) เท่านั้น** มองขึ้นลงแล้วความเร็วไม่เปลี่ยน
- **ระบบโต้ตอบแยกเป็นคอมโพเนนต์** วัตถุใดก็โต้ตอบได้แค่เพิ่มโหนด `Interactable` (หรือคลาสลูก) + `CollisionShape3D` ระบบนี้ไม่รู้จัก UI และไม่รู้จักผู้เล่นโดยตรง จึงใช้ต่อกับ NPC และ co-op ในอนาคตได้
- **Physics layers**: 1 world · 2 player · 3 interactable · 4 npc (ตั้งชื่อไว้ใน Project Settings แล้ว)

## 3. ไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `project.godot` | ตั้งค่าโปรเจกต์, input map, autoload, physics layer, physics interpolation |
| `scripts/managers/event_bus.gd` | Autoload `EventBus` |
| `scripts/managers/game_manager.gd` | Autoload `GameManager` |
| `scripts/player/player_controller.gd` | `PlayerController` — เดิน วิ่ง กระโดด หันตัว |
| `scripts/player/player_camera_rig.gd` | `PlayerCameraRig` — กล้อง orbit, ซูม, SpringArm |
| `scripts/interaction/interactable.gd` | `Interactable` — คลาสฐานของวัตถุที่โต้ตอบได้ |
| `scripts/interaction/info_sign.gd` | `InfoSign` — ป้ายที่แสดงข้อความบน HUD |
| `scripts/interaction/interaction_detector.gd` | `InteractionDetector` — หาวัตถุที่ดีที่สุดหน้าผู้เล่นแล้วกด E |
| `scripts/world/world_layout.gd` | `WorldLayout` — อ่าน JSON, หา chunk ของตำแหน่ง |
| `scripts/world/greybox_builder.gd` | `GreyboxBuilder` — สร้างพื้น ภูมิภาค น้ำ ถนน สะพาน อาคาร ป้าย ขอบโลก |
| `scripts/world/world_manager.gd` | `WorldManager` — วางผู้เล่น, ส่ง `player_chunk_changed` |
| `scripts/ui/main_menu.gd`, `pause_menu.gd`, `hud.gd` | UI |
| `shaders/greybox_grid.gdshader` | พื้นตาราง 1 ม. / 10 ม. / เส้น chunk 125 ม. |
| `scenes/main/main_menu.tscn` | ฉากเริ่มต้นของเกม |
| `scenes/world/world.tscn` | โลก |
| `scenes/player/player.tscn` | ผู้เล่น |
| `scenes/ui/hud.tscn`, `pause_menu.tscn`, `haven_theme.tres` | UI และธีม |
| `tests/phase1_test.tscn`, `.gd` | ทดสอบอัตโนมัติ |

## 4. โครงสร้างฉาก (Scene hierarchy)

```
World (Node3D) ─ world_manager.gd
├─ WorldEnvironment        ท้องฟ้า ProceduralSky, หมอกบางๆ, tonemap Filmic
├─ Sun (DirectionalLight3D) เงาเปิด, ระยะเงา 160 ม.
├─ Greybox (Node3D) ─ greybox_builder.gd   ลูกทั้งหมดถูกสร้างตอนเริ่มเกม:
│    Ground · Regions · Water · Roads · Bridges · Landmarks (อาคาร + ป้าย Sign_<id>) · VillageDetails · WorldEdges
├─ Player (player.tscn)
├─ HUD (hud.tscn)
└─ PauseMenu (pause_menu.tscn)

Player (CharacterBody3D) ─ player_controller.gd   layer 2 · mask 1 · group "player"
├─ CollisionShape3D        Capsule r 0.35 h 1.75 (ยกขึ้น 0.875 ให้ origin อยู่ที่เท้า)
├─ Model (Node3D)          หมุนตามทิศเดิน
│  ├─ Body, Face           แคปซูลชั่วคราว (โมเดลจริง Phase 7)
│  └─ InteractionDetector (Area3D) ─ interaction_detector.gd   mask 3
│     └─ CollisionShape3D  Sphere r 1.6 อยู่หน้าตัว 1.1 ม.
└─ CameraRig (Node3D) ─ player_camera_rig.gd
   └─ Pitch (Node3D)
      └─ SpringArm3D       ยาว 4.5 ม. · Sphere r 0.25 · mask 1
         └─ Camera3D       FOV 70 · far 1500
```

## 5. การตั้งค่าใน Inspector

| โหนด | ค่าที่ปรับได้ |
|---|---|
| Player | Walk Speed 4, Run Speed 7, Acceleration 30, Deceleration 40, Air Acceleration 8, Turn Speed 12, Jump Height 1.2, Coyote Time 0.12, Jump Buffer Time 0.12 |
| Player/CameraRig | Height Offset 1.5, Mouse Sensitivity 0.0025, Invert Y, Min/Max Pitch −70°/40°, Min/Max Distance 2/8, Zoom Step 0.5 |
| Player/Model/InteractionDetector | Facing Weight 1.0 (0 = เลือกอันที่ใกล้สุดเสมอ) |
| World/Greybox | Layout Json = `world_layout.json`, Show Labels, Build Signs, ปุ่ม **Rebuild Preview** |
| World | Spawn Marker (เว้นว่าง = ใช้จุดเกิดจาก JSON), Spawn Look At Landmark = `town_hall` |
| HUD | Notification Duration 4 วินาที |
| Interactable / InfoSign | Prompt, Enabled, Title, Message |

## 6. Signal

ทั้งหมดอยู่ใน `EventBus` และเชื่อมด้วยโค้ด (ไม่ต้องต่อใน editor)

| Signal | ผู้ส่ง | ผู้ฟัง |
|---|---|---|
| `game_paused(is_paused)` | GameManager | PauseMenu |
| `interaction_target_changed(prompt)` | InteractionDetector | HUD (ข้อความ "[E] …") |
| `interacted(target, interactor)` | Interactable | (ระบบในอนาคต: ภารกิจ, สถิติ) |
| `notification_requested(title, message)` | InfoSign | HUD |
| `player_chunk_changed(chunk)` | WorldManager | HUD (ดีบัก) |

Signal ระดับโหนด: `Interactable.interacted(interactor)` ต่อได้จาก editor สำหรับวัตถุเฉพาะ

## 7. วิธีทดสอบ

**เปิดโปรเจกต์** Godot 4.7.2 → Import → เลือก `Documents\HavenValley\project.godot` → กด F5

ทดสอบด้วยตัวเอง
1. เมนูหลักขึ้น ปุ่ม Continue เป็นสีเทา (ระบบเซฟมาใน Phase 6)
2. New Game → เกิดในฟาร์ม หันไปทางหอนาฬิกาสีแดงของศาลากลาง
3. ขยับเมาส์ → กล้องหมุน · ล้อเมาส์ → ซูม · WASD เดิน · Shift วิ่ง · Space กระโดด
4. เดินไปที่ป้ายไม้หน้าบ่อน้ำ → เห็น **[E] Read sign** → กด E → กล่องข้อความ "Water Well" ขึ้นด้านบน
5. วิ่งไปศาลากลาง (ประมาณ 45 วินาที) แล้วหันหลังชิดกำแพง → กล้องต้องไม่ทะลุเข้าไปในอาคาร
6. F3 → ดูพิกัดและ chunk (ฟาร์ม = C6, ศาลากลาง = E4)
7. ESC → เมนูหยุดเกม → Resume / Main Menu ใช้ได้
8. คลิกนอกหน้าต่างแล้วคลิกกลับ → เมาส์ถูกจับกลับเข้าเกม

ทดสอบอัตโนมัติ: เปิด `tests/phase1_test.tscn` แล้วกด **F6** ดูผลในแท็บ Output (27 ข้อ ต้องขึ้น `27 passed, 0 failed`)
หรือใช้คำสั่ง: `godot --headless --path . res://tests/phase1_test.tscn --fixed-fps 60`

## 8. ข้อจำกัดที่รู้อยู่แล้ว (ตั้งใจ)

- โลกแบน: ภูเขาเป็นแค่พื้นสีเทา ความสูงจริงมาใน Phase 2
- น้ำเป็นแถบสีบนพื้น เดินทับได้ ไม่มีการว่ายน้ำ (Phase 2–5)
- สะพานและถนนเป็นภาพอย่างเดียว ไม่มี collision เพราะพื้นแบนอยู่แล้ว
- ผู้เล่นเป็นแคปซูล ไม่มีแอนิเมชัน (Phase 7)
- ข้อความในเกมยังเป็นภาษาอังกฤษ ระบบหลายภาษามาใน Phase 7

## 9. ขั้นต่อไป (Phase 2)

ทดสอบ Terrain3D กับ Godot 4.7.2 → heightmap ตามแผนความสูง → แหล่งน้ำและ water shader → ถนนและสะพานจริง → blockout อาคารจาก Blender
