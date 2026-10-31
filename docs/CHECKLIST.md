# Haven Valley — Development Checklist

สถานะ: ✅ เสร็จและทดสอบแล้ว · 🟡 กำลังทำ · ⬜ ยังไม่เริ่ม
แผนเต็มของแต่ละเฟสอยู่ใน [`ROADMAP.md`](ROADMAP.md)

## Phase 0 — แบบแปลน ✅
- ✅ แผนที่โลกและระบบพิกัด (blueprint v0.2)
- ✅ ตารางพิกัด ภูมิภาค ความสูง ถนน แหล่งน้ำ พื้นที่ก่อสร้าง
- ✅ กลยุทธ์ภูมิประเทศ, รายการแอสเซ็ต Blender, ขั้นตอน W1–W9
- ✅ ไฟล์ `resources/world/world_layout.json`
- ✅ ตัดสินใจ: Terrain3D, Godot 4.7.2, ฟาร์มตะวันตกเฉียงใต้, โฟลเดอร์โปรเจกต์

## Phase 1 — รากฐาน ✅
- ✅ โปรเจกต์ Godot 4.7.2 และโครงสร้างโฟลเดอร์
- ✅ Input map (WASD, Shift, Space, E, ESC, F3) ใช้ physical key รองรับคีย์บอร์ดภาษาไทย
- ✅ Autoload `EventBus`, `GameManager`
- ✅ เมนูหลัก, เมนูหยุดเกม
- ✅ ตัวควบคุมผู้เล่นบุคคลที่สาม (เดิน วิ่ง กระโดด coyote time / jump buffer)
- ✅ กล้อง orbit + SpringArm3D + ซูม + physics interpolation
- ✅ โลก greybox จาก `world_layout.json` (W1)
- ✅ ระบบโต้ตอบ `Interactable` / `InteractionDetector` / `InfoSign`
- ✅ HUD (ข้อความโต้ตอบ, การแจ้งเตือน, ดีบัก F3)
- ✅ ฉากทดสอบอัตโนมัติ `tests/phase1_test.tscn` ผ่าน 27/27 ใน Godot 4.7.2
- ✅ ผู้ใช้อนุมัติให้ทำต่อ

## Phase 2 — ต้นแบบโลก 🟡
2A ภูมิประเทศและน้ำ ✅
- ✅ ทดสอบ Terrain3D v1.0.2 กับ Godot 4.7.2 — ผ่าน
- ✅ Heightmap จากแบบแปลน (W2) — สถานที่ทุกแห่งตรงความสูง 0.00 ม.
- ✅ ภูมิประเทศในตัว Godot: 64 tile + HeightMapShape3D + shader พื้น
- ✅ แหล่งน้ำ + water shader + น้ำตก (W3)
- ✅ ถนนตามความชัน + สะพาน 8 แห่ง + ท่าเรือ 2 แห่ง (W4)
- ✅ ชื่อภูมิภาค, กันตกน้ำลึก
- ✅ ทดสอบอัตโนมัติ `tests/phase2_test.tscn` 18/18 และ Phase 1 ยังผ่าน 27/27 (ตอนจบ 2A)

2B Terrain3D ✅
- ✅ ผู้ใช้ติดตั้ง Terrain3D 1.1.0 จาก AssetLib — ทดสอบซ้ำกับ Godot 4.7.2 ผ่าน
- ✅ ข้อมูล Terrain3D 25 region จาก heightmap
- ✅ Shader Terrain3D สไตล์ Haven Valley (หน้าตาเหมือนภูมิประเทศเดิม)
- ✅ `TerrainSystem` เลือก Terrain3D / ภูมิประเทศสำรองอัตโนมัติ
- ✅ ฉากปั้นพื้น `terrain_editor.tscn` + เครื่องมือ import / export
- ✅ ทดสอบผ่านทั้งสองระบบ (Phase 2 19/19, Phase 1 27/27)
- ✅ เชื่อม GitHub `Newclaffly/HavenValley` (commit แยกตามเฟส)

2C แอสเซ็ตชุดแรก ✅
- ✅ สคริปต์ Blender `tools/blender/haven_blockouts.py` สร้างโมเดล 32 ชิ้นจากแบบแปลน (ทดสอบกับ Blender 5.2.3)
- ✅ Blockout อาคาร 15 หลัง + บ้าน 3 แบบ + แผงตลาด 3 แบบ พร้อม collision (W5)
- ✅ ต้นไม้ พุ่มไม้ หิน 11 แบบ + `NatureScatter` (MultiMesh แยก chunk, collision ลำต้น/หิน)
- ✅ ทดสอบ `tests/phase2c_test.tscn` 20/20 ทั้งสองระบบภูมิประเทศ, Phase 2 19/19, Phase 1 27/27

## Phase 3 — ระบบเกมพื้นฐาน ⬜
- ⬜ ไอเท็ม / Inventory / Hotbar
- ⬜ เก็บทรัพยากร
- ⬜ ฟาร์ม: พืช 3 ชนิด
- ⬜ ก่อสร้างพื้นฐาน (W6)

## Phase 4 — การใช้ชีวิต ⬜
- ⬜ NPC + ตารางชีวิต · ⬜ บทสนทนา · ⬜ ร้านค้า/เศรษฐกิจ · ⬜ สัตว์ · ⬜ คราฟต์

## Phase 5 — ขยายโลก ⬜
- ⬜ ป่า ภูเขา ทะเลสาบ ถ้ำ · ⬜ ตกปลา ขุดแร่ · ⬜ พืชพรรณ + ID (W7) · ⬜ งานภาพ MVP (W8)

## Phase 6 — ระบบโลก ⬜
- ⬜ TimeManager · ⬜ สภาพอากาศ · ⬜ ฤดูกาล · ⬜ SaveManager · ⬜ Progression

## Phase 7 — ขัดเกลา ⬜
- ⬜ UI ครบ · ⬜ เสียง · ⬜ แอนิเมชัน · ⬜ ประสิทธิภาพ (W9) · ⬜ ภาษาไทย/อังกฤษ

## Phase 8 — อนาคต ⬜
- ⬜ Co-op · ⬜ ก่อสร้างขั้นสูง · ⬜ ภูมิภาคใหม่
