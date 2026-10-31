# Haven Valley

Cozy 2D isometric life simulation — farming, house building, exploration and crafting.
Godot **4.7.2** · GDScript · 2D isometric vector-cartoon art (128 × 64 px tiles) · Windows PC

> เวอร์ชัน 3D เดิม (Phase 0–2C) อยู่ใน branch `prototype-3d`

## เปิดโปรเจกต์
1. เปิด Godot 4.7.2 → **Import** → เลือก `project.godot` ในโฟลเดอร์นี้
2. กด **F5** เพื่อเล่นจากเมนูหลัก หรือเปิด `scenes/world/world.tscn` แล้วกด **F6** เพื่อเข้าโลกทันที

## ปุ่มควบคุม
WASD / ลูกศร เดิน (ตามทิศบนจอ) · Shift วิ่ง · E โต้ตอบ · ESC หยุดเกม · F3 ข้อมูลดีบัก
(จองไว้สำหรับ Phase 3: คลิกซ้าย / F ใช้เครื่องมือ · 1–8 เลือกช่อง Hotbar · Tab / I กระเป๋า)

## เอกสาร
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — แผนทุกเฟส
- [`docs/CHECKLIST.md`](docs/CHECKLIST.md) — สถานะงาน
- [`docs/PIVOT_2D.md`](docs/PIVOT_2D.md) — เหตุผลและแผนการเปลี่ยนเป็น 2D
- [`docs/P1_2D.md`](docs/P1_2D.md) — P1-2D: ฉาก สคริปต์ Inspector signal และวิธีทดสอบ
- `resources/world/world_layout.json` — พิกัดโลกทั้งหมด (เมตร) แปลงเป็น tile ด้วย `WorldLayout.to_pixels()`

## ภาพ
ภาพทั้งหมดวาดด้วยโค้ดใน `tools/art/iso_art.py` (SVG → PNG) ผลอยู่ใน `assets/art/`
สร้างใหม่: `python tools/art/iso_art.py` (ต้องมี Python + Pillow และ Node.js + playwright)

## ทดสอบอัตโนมัติ
```
godot --headless --path . res://tests/p1_2d_test.tscn
```
หรือเปิด `tests/p1_2d_test.tscn` แล้วกด F6 (ผลอยู่ในแท็บ Output)

## Git
https://github.com/Newclaffly/HavenValley — commit แยกตามเฟส
