import 'package:flutter/material.dart';

import '../db.dart';
import '../message_builder.dart';
import '../models.dart';
import '../sos_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  final _nameCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await AppDb.instance.contacts();
    final n = await AppDb.instance.getSetting('user_name') ?? '';
    if (!mounted) return;
    setState(() {
      _contacts = c;
      _nameCtl.text = n;
    });
  }

  Future<void> _saveName(String v) async {
    await AppDb.instance.setSetting('user_name', v.trim());
    await SosService.instance.syncNative();
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final relation = TextEditingController();
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add emergency contact'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Phone (with country code)', errorText: error),
            ),
            TextField(controller: relation, decoration: const InputDecoration(labelText: 'Relation (optional)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setD(() => error = null);
                  return;
                }
                if (normalizePhone(phone.text) == null) {
                  setD(() => error = 'Enter a valid number');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await AppDb.instance.addContact(Contact(
        name: name.text.trim(),
        phone: normalizePhone(phone.text)!,
        relation: relation.text.trim(),
      ));
      await SosService.instance.syncNative();
      _load();
    }
  }

  Future<void> _delete(Contact c) async {
    await AppDb.instance.deleteContact(c.id!);
    await SosService.instance.syncNative();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtl,
            decoration: const InputDecoration(
              labelText: 'Your name (shown in the alert)',
              border: OutlineInputBorder(),
            ),
            onChanged: _saveName,
          ),
          const SizedBox(height: 16),
          if (_contacts.isEmpty)
            const Text('No contacts yet. Add the people who should receive your SOS.'),
          for (final c in _contacts)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(c.name),
                subtitle: Text(c.relation.isEmpty ? c.phone : '${c.relation}  -  ${c.phone}'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(c)),
              ),
            ),
        ],
      ),
    );
  }
}
