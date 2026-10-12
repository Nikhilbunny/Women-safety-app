import 'package:flutter/material.dart';

import '../alarm_service.dart';
import '../call_service.dart';
import '../db.dart';
import 'camera_screen.dart';

/// Call contacts, record video evidence, and the loud alarm.
class ToolsPanel extends StatefulWidget {
  const ToolsPanel({super.key});

  @override
  State<ToolsPanel> createState() => _ToolsPanelState();
}

class _ToolsPanelState extends State<ToolsPanel> {
  String _sound = 'siren';
  bool _alarmOnSos = false;
  bool _callOnSos = false;

  @override
  void initState() {
    super.initState();
    _load();
    AlarmService.playing.addListener(_rebuild);
  }

  @override
  void dispose() {
    AlarmService.playing.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final sound = await AppDb.instance.getSetting('alarm_sound');
    final a = await AppDb.instance.getSetting('alarm_on_sos') == '1';
    final c = await AppDb.instance.getSetting('call_on_sos') == '1';
    if (!mounted) return;
    setState(() {
      if (sound != null && AlarmService.sounds.containsKey(sound)) _sound = sound;
      _alarmOnSos = a;
      _callOnSos = c;
    });
  }

  Future<void> _setBool(String key, bool v) async {
    await AppDb.instance.setSetting(key, v ? '1' : '0');
  }

  Future<void> _toggleAlarm() async {
    if (AlarmService.playing.value) {
      await AlarmService.stop();
    } else {
      await AlarmService.start(_sound);
    }
  }

  Future<void> _openCallSheet() async {
    final contacts = await AppDb.instance.contacts();
    if (!mounted) return;
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an emergency contact first')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Call emergency contacts', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.phone_in_talk),
              label: const Text('Call all in order'),
              onPressed: () {
                Navigator.pop(ctx);
                CallService.instance.startChain(contacts);
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Calls the first contact. When the call ends and you return here, you can call the next.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            for (final c in contacts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person),
                title: Text(c.name),
                subtitle: Text(c.relation.isEmpty ? c.phone : '${c.relation}  -  ${c.phone}'),
                trailing: const Icon(Icons.call),
                onTap: () {
                  Navigator.pop(ctx);
                  CallService.instance.callOne(c);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playing = AlarmService.playing.value;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.call),
                label: const Text('Call contacts'),
                onPressed: _openCallSheet,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.videocam),
                label: const Text('Record video'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CameraScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Loud alarm', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _sound,
                        items: AlarmService.sounds.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _sound = v);
                          await AppDb.instance.setSetting('alarm_sound', v);
                          if (AlarmService.playing.value) await AlarmService.start(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: playing ? FilledButton.styleFrom(backgroundColor: scheme.error) : null,
                      icon: Icon(playing ? Icons.volume_off : Icons.volume_up),
                      label: Text(playing ? 'Stop' : 'Sound'),
                      onPressed: _toggleAlarm,
                    ),
                  ],
                ),
                Text(
                  'Plays at full alarm volume, even if the phone is on silent. Stops by itself after 5 minutes.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('Sound the alarm when SOS is sent'),
          value: _alarmOnSos,
          onChanged: (v) {
            setState(() => _alarmOnSos = v);
            _setBool('alarm_on_sos', v);
          },
        ),
        SwitchListTile(
          title: const Text('Start calling my contacts after SOS'),
          subtitle: const Text('Calls the first contact, then offers the next. The alarm stops when a call starts.'),
          value: _callOnSos,
          onChanged: (v) {
            setState(() => _callOnSos = v);
            _setBool('call_on_sos', v);
          },
        ),
      ],
    );
  }
}
