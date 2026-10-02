import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Classroom demo only: local storage is not a server-side security boundary.
class Chapter4Store {
  final SharedPreferencesAsync preferences = SharedPreferencesAsync();
  static const accountsKey = 'chapter4.accounts.v1';

  Future<Map<String, dynamic>> read(String key) async {
    final value = await preferences.getString(key);
    return value == null ? {} : jsonDecode(value) as Map<String, dynamic>;
  }

  Future<String> passwordHash(String password, List<int> salt) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    return base64Encode(await key.extractBytes());
  }

  Future<void> register(String email, String password) async {
    final accounts = await read(accountsKey);
    if (accounts.containsKey(email)) {
      throw const FormatException('อีเมลนี้ลงทะเบียนแล้ว');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    accounts[email] = {
      'salt': base64Encode(salt),
      'hash': await passwordHash(password, salt),
    };
    await preferences.setString(accountsKey, jsonEncode(accounts));
  }

  Future<void> login(String email, String password) async {
    final accounts = await read(accountsKey);
    final account = accounts[email] as Map<String, dynamic>?;
    if (account == null ||
        await passwordHash(password, base64Decode(account['salt'] as String)) !=
            account['hash']) {
      throw const FormatException('อีเมลหรือรหัสผ่านไม่ถูกต้อง');
    }
  }

  String albumKey(String email) => 'chapter4.albums.v1.$email';

  Future<List<String>> memberEmails() async {
    final accounts = await read(accountsKey);
    return accounts.keys.toList()..sort();
  }

  Future<List<Map<String, dynamic>>> albums(String email) async {
    final data = await read(albumKey(email));
    return (data['albums'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<void> save(String email, List<Map<String, dynamic>> albums) =>
      preferences.setString(albumKey(email), jsonEncode({'albums': albums}));
}

class Chapter4Page extends StatefulWidget {
  const Chapter4Page({super.key});

  @override
  State<Chapter4Page> createState() => _Chapter4PageState();
}

class _Chapter4PageState extends State<Chapter4Page> {
  final store = Chapter4Store();
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  String? user;
  String? error;
  bool register = false;
  bool busy = false;
  bool obscure = true;
  List<Map<String, dynamic>> albums = [];

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void showMembers() {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => MembersPage(store: store, currentUser: user),
    ));
  }

  Future<void> authenticate() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    final address = email.text.trim().toLowerCase();
    try {
      if (register) {
        await store.register(address, password.text);
        if (!mounted) return;
        setState(() => register = false);
        password.clear();
        confirm.clear();
        message('ลงทะเบียนสำเร็จ กรุณาเข้าสู่ระบบ');
      } else {
        await store.login(address, password.text);
        final loaded = await store.albums(address);
        if (!mounted) return;
        setState(() { user = address; albums = loaded; });
        password.clear();
        confirm.clear();
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'อ่านหรือบันทึกข้อมูลไม่ได้ กรุณาลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> persist(List<Map<String, dynamic>> next) async {
    if (busy || user == null) return;
    setState(() => busy = true);
    try {
      await store.save(user!, next);
      if (!mounted) return;
      setState(() => albums = next);
      message('บันทึกข้อมูลแล้ว');
    } catch (_) {
      message('บันทึกไม่สำเร็จ ข้อมูลเดิมยังอยู่ กรุณาลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([Map<String, dynamic>? album]) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => AlbumEditor(initial: album?['title'] as String?),
    );
    if (!mounted || title == null || busy) return;
    final next = albums.map((item) => Map<String, dynamic>.from(item)).toList();
    if (album == null) {
      final id = next.fold<int>(0, (maxId, item) => max(maxId, item['id'] as int)) + 1;
      next.add({'id': id, 'title': title});
    } else {
      next.firstWhere((item) => item['id'] == album['id'])['title'] = title;
    }
    await persist(next);
  }

  Future<void> remove(Map<String, dynamic> album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบอัลบั้ม?'),
        content: Text('ต้องการลบ “${album['title']}” หรือไม่'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (!mounted || confirmed != true || busy) return;
    await persist(albums.where((item) => item['id'] != album['id']).toList());
  }

  Future<void> importExamples() async {
    if (busy || user == null) return;
    setState(() => busy = true);
    try {
      final response = await http.get(
        Uri.parse('https://jsonplaceholder.typicode.com/albums?userId=1'),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final examples = jsonDecode(response.body) as List;
      final next = albums.map((item) => Map<String, dynamic>.from(item)).toList();
      var id = next.fold<int>(0, (maxId, item) => max(maxId, item['id'] as int));
      final knownTitles = next.map((item) => item['title']).toSet();
      for (final example in examples.take(3)) {
        final title = example['title'] as String;
        if (knownTitles.add(title)) next.add({'id': ++id, 'title': title});
      }
      await store.save(user!, next);
      if (!mounted) return;
      setState(() => albums = next);
      message('นำเข้าข้อมูลตัวอย่างแล้ว');
    } catch (_) {
      message('นำเข้าไม่สำเร็จ ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) return authenticationForm();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('อัลบั้มของ $user', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('ข้อมูลบันทึกในเครื่องนี้ แยกตามบัญชีผู้ใช้'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: busy ? null : () => edit(), icon: const Icon(Icons.add), label: const Text('เพิ่มอัลบั้ม')),
              OutlinedButton.icon(onPressed: busy ? null : importExamples, icon: const Icon(Icons.cloud_download), label: const Text('ดึงตัวอย่าง 3 รายการ')),
              OutlinedButton.icon(onPressed: busy ? null : showMembers, icon: const Icon(Icons.people), label: const Text('รายชื่อสมาชิกทั้งหมด')),
              TextButton.icon(onPressed: busy ? null : () {
                setState(() { user = null; albums = []; error = null; register = false; });
              }, icon: const Icon(Icons.logout), label: const Text('ออกจากระบบ')),
            ]),
          ]),
        ),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: albums.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('ยังไม่มีอัลบั้ม กดเพิ่มอัลบั้มหรือดึงข้อมูลตัวอย่าง')))
              : ListView.builder(
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text(album['title'] as String),
                        subtitle: Text('ID: ${album['id']}'),
                        onTap: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
                          title: const Text('รายละเอียดอัลบั้ม'),
                          content: Text('ID: ${album['id']}\nชื่อ: ${album['title']}\nเจ้าของ: $user'),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด'))],
                        )),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'แก้ไข', onPressed: busy ? null : () => edit(album), icon: const Icon(Icons.edit)),
                          IconButton(tooltip: 'ลบ', onPressed: busy ? null : () => remove(album), icon: const Icon(Icons.delete_outline)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget authenticationForm() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Form(
          key: form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.account_circle, size: 64, color: Colors.deepPurple),
            const SizedBox(height: 16),
            Text(register ? 'ลงทะเบียน' : 'เข้าสู่ระบบ', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('บทที่ 4 • ระบบอัลบั้ม CRUD\nบัญชีสาธิตใช้ได้เฉพาะเครื่อง/เบราว์เซอร์นี้', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextFormField(
              controller: email, enabled: !busy, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'อีเมล', border: OutlineInputBorder()),
              validator: (value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value?.trim() ?? '') ? null : 'กรอกอีเมลให้ถูกต้อง',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: password, enabled: !busy, obscureText: obscure,
              decoration: InputDecoration(labelText: 'รหัสผ่าน', border: const OutlineInputBorder(), suffixIcon: IconButton(
                tooltip: obscure ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              )),
              validator: (value) => (value ?? '').length < 8 ? 'รหัสผ่านอย่างน้อย 8 ตัวอักษร' : null,
            ),
            if (register) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: confirm, enabled: !busy, obscureText: true,
                decoration: const InputDecoration(labelText: 'ยืนยันรหัสผ่าน', border: OutlineInputBorder()),
                validator: (value) => value != password.text ? 'รหัสผ่านไม่ตรงกัน' : null,
              ),
            ],
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 24),
            if (busy) const LinearProgressIndicator(),
            FilledButton(onPressed: busy ? null : authenticate, child: Text(register ? 'ลงทะเบียน' : 'เข้าสู่ระบบ')),
            TextButton(onPressed: busy ? null : () {
              form.currentState?.reset();
              setState(() { register = !register; error = null; });
              password.clear(); confirm.clear();
            }, child: Text(register ? 'มีบัญชีแล้ว? เข้าสู่ระบบ' : 'ยังไม่มีบัญชี? ลงทะเบียน')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : showMembers,
              icon: const Icon(Icons.people),
              label: const Text('รายชื่อสมาชิกทั้งหมด'),
            ),
          ]),
        ),
      ),
    ),
  );
}

class MembersPage extends StatefulWidget {
  const MembersPage({super.key, required this.store, this.currentUser});

  final Chapter4Store store;
  final String? currentUser;

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  late Future<List<String>> members;

  @override
  void initState() {
    super.initState();
    members = widget.store.memberEmails();
  }

  void refresh() {
    setState(() => members = widget.store.memberEmails());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('รายชื่อสมาชิกทั้งหมด'),
      actions: [
        IconButton(
          tooltip: 'โหลดรายชื่อใหม่',
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<String>>(
      future: members,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('โหลดรายชื่อไม่ได้ กรุณาลองอีกครั้ง'),
              const SizedBox(height: 12),
              FilledButton(onPressed: refresh, child: const Text('ลองใหม่')),
            ]),
          ));
        }
        final emails = snapshot.data ?? const <String>[];
        return Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Icon(Icons.groups, size: 48, color: Colors.deepPurple),
              const SizedBox(height: 8),
              Text('สมาชิกทั้งหมด ${emails.length} บัญชี',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('บัญชีที่ลงทะเบียนในเบราว์เซอร์นี้เท่านั้น',
                  textAlign: TextAlign.center),
            ]),
          ),
          Expanded(
            child: emails.isEmpty
                ? const Center(child: Text('ยังไม่มีสมาชิก กรุณาลงทะเบียนก่อน'))
                : ListView.builder(
                    itemCount: emails.length,
                    itemBuilder: (context, index) => Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(emails[index]),
                        subtitle: emails[index] == widget.currentUser
                            ? const Text('บัญชีที่กำลังเข้าสู่ระบบ') : null,
                      ),
                    ),
                  ),
          ),
        ]);
      },
    ),
  );
}

class AlbumEditor extends StatefulWidget {
  const AlbumEditor({super.key, this.initial});
  final String? initial;

  @override
  State<AlbumEditor> createState() => _AlbumEditorState();
}

class _AlbumEditorState extends State<AlbumEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.initial);

  @override
  void dispose() { title.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'เพิ่มอัลบั้ม' : 'แก้ไขอัลบั้ม'),
    content: Form(key: form, child: TextFormField(
      controller: title, autofocus: true, maxLength: 200,
      decoration: const InputDecoration(labelText: 'ชื่ออัลบั้ม'),
      validator: (value) => (value ?? '').trim().isEmpty ? 'กรอกชื่ออัลบั้ม' : null,
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
      FilledButton(onPressed: () {
        if (form.currentState!.validate()) Navigator.pop(context, title.text.trim());
      }, child: const Text('บันทึก')),
    ],
  );
}
