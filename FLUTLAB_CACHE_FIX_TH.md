# แก้ collection 1.19.1 ขาดไฟล์ใน FlutLab

ชุดนี้มีแพ็กเกจต้นฉบับ collection 1.19.1 จาก pub.dev อยู่ใน vendor/collection พร้อม LICENSE และตั้ง dependency_overrides ใน pubspec.yaml ให้ใช้ไฟล์ในโปรเจกต์แทน hosted cache

ตรวจ SHA256 ของ archive กับ pub.dev แล้ว:
2f5709ae4d3d59dd8f7cd309b4e023046b57d8a6c82130785d2b0e5868084e76

วิธีใช้:
1. นำเข้า ZIP ชุด cachefix เป็นโปรเจกต์ใหม่ใน FlutLab หรือคัดลอกโฟลเดอร์ vendor ทั้งโฟลเดอร์และ pubspec.yaml ไปในโปรเจกต์เดิมที่มีโค้ด CRUD แล้ว
2. ตรวจว่า vendor/collection/pubspec.yaml อยู่ในโปรเจกต์จริง
3. กด Pub Get ให้สำเร็จ แล้ว Run Web

หาก error ยังอ้าง .pub-cache/hosted/pub.dev/collection-1.19.1 แสดงว่าการ build ยังไม่ได้ใช้ path override นี้ ให้ตรวจไฟล์ pubspec.yaml และผล Pub Get ของโปรเจกต์ที่กำลังเปิด

ตรวจความครบของไฟล์ที่หายใน log แล้ว แต่ยังไม่ได้รัน build ใน FlutLab จึงยังยืนยันผล compile ไม่ได้ วิธีนี้แก้เฉพาะ collection หาก cache แพ็กเกจอื่นเสียด้วยต้องซ่อม cache ฝั่งบริการ

เมื่อ FlutLab ซ่อม cache แล้ว สามารถนำ dependency_overrides ส่วนนี้ออกและกด Pub Get เพื่อกลับไปใช้แพ็กเกจจาก pub.dev ตามปกติ
