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
- ✅ ทดสอบอัตโนมัติ `tests/phase2_test.tscn` 18/18 และ Phase 1 ยังผ่าน 27/27

2B Terrain3D ⬜
- ⬜ ผู้ใช้ติดตั้ง Terrain3D จาก AssetLib (ดู PHASE2.md ข้อ 3)
- ⬜ นำ heightmap เข้า Terrain3D + เท็กซ์เจอร์ + ปั้น/ระบายใน editor

2C แอสเซ็ตชุดแรก ⬜
- ⬜ Blockout อาคารจาก Blender (W5)
- ⬜ ต้นไม้และหินชุดแรก

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
