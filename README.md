# Haven Valley

Cozy open-world life simulation — farming, house building, exploration and crafting.
Godot **4.7.2** · GDScript · Blender (glTF) · Windows PC

## เปิดโปรเจกต์
1. เปิด Godot 4.7.2 → **Import** → เลือก `project.godot` ในโฟลเดอร์นี้
2. กด **F5** เพื่อเล่นจากเมนูหลัก หรือเปิด `scenes/world/world.tscn` แล้วกด **F6** เพื่อเข้าโลกทันที

## ปุ่มควบคุม
WASD เดิน · Shift วิ่ง · Space กระโดด · เมาส์ หมุนกล้อง · ล้อเมาส์ ซูม · E โต้ตอบ · ESC หยุดเกม · F3 ข้อมูลดีบัก

## เอกสาร
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — แผนทุกเฟส
- [`docs/CHECKLIST.md`](docs/CHECKLIST.md) — สถานะงาน
- [`docs/PHASE1.md`](docs/PHASE1.md) — Phase 1: สถาปัตยกรรม ฉาก Inspector signal และวิธีทดสอบ
- [`docs/PHASE2.md`](docs/PHASE2.md) — Phase 2: ภูมิประเทศ น้ำ ถนน สะพาน, ผลทดสอบและวิธีติดตั้ง Terrain3D
- `resources/world/world_layout.json` — พิกัดโลกทั้งหมด (v0.3)
- `tools/terrain/` — สร้างภูมิประเทศใหม่จากแบบแปลน

## ทดสอบอัตโนมัติ
เปิด `tests/phase1_test.tscn` หรือ `tests/phase2_test.tscn` แล้วกด F6 (ผลอยู่ในแท็บ Output)
