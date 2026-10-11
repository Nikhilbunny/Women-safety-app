import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db.dart';
import '../helplines.dart';
import '../models.dart';
import '../shake_detector.dart';
import '../sos_service.dart';
import 'contacts_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _svc = SosService.instance;
  late final ShakeDetector _shake = ShakeDetector(onShake: () => _startSos('shake'));
  Timer? _retryTimer;

  bool _shakeOn = false;
  bool _countdownOpen = false;
  List<SosEvent> _events = [];
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // Offline queue: try again every minute in case signal came back.
    _retryTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _svc.flushOutbox();
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _shake.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final events = await AppDb.instance.events();
    final pending = (await AppDb.instance.outbox()).length;
    final shakeSaved = await AppDb.instance.getSetting('shake_on') == '1';
    if (!mounted) return;
    setState(() {
      _events = events;
      _pending = pending;
      if (shakeSaved != _shakeOn) {
        _shakeOn = shakeSaved;
        shakeSaved ? _shake.start() : _shake.stop();
      }
    });
  }

  Future<void> _toggleShake(bool on) async {
    await AppDb.instance.setSetting('shake_on', on ? '1' : '0');
    on ? _shake.start() : _shake.stop();
    setState(() => _shakeOn = on);
  }

  Future<void> _startSos(String source) async {
    if (_countdownOpen || !mounted) return;
    _countdownOpen = true;
    HapticFeedback.heavyImpact();
    // 5 second cancel window prevents accidental alerts.
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CountdownDialog(),
    );
    _countdownOpen = false;
    if (go == true) {
      await _svc.trigger(source: source);
      await _load();
    }
  }

  Future<void> _call(String number) async {
    await launchUrl(Uri.parse('tel:$number'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety App'),
        actions: [
          IconButton(
            tooltip: 'Emergency contacts',
            icon: const Icon(Icons.contacts),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen()));
              _load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_pending > 0)
            Card(
              color: Colors.orange.shade100,
              child: ListTile(
                leading: const Icon(Icons.signal_cellular_connected_no_internet_0_bar),
                title: Text('$_pending alert(s) waiting for signal'),
                trailing: TextButton(
                  onPressed: () async {
                    await _svc.flushOutbox();
                    _load();
                  },
                  child: const Text('Retry now'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: () => _startSos('phone'),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.error,
                  boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black26)],
                ),
                alignment: Alignment.center,
                child: const Text('SOS',
                    style: TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<String>(
            valueListenable: _svc.status,
            builder: (_, s, __) => Center(child: Text(s, textAlign: TextAlign.center)),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Shake phone 3 times to send SOS'),
            subtitle: const Text('Works while the app is open'),
            value: _shakeOn,
            onChanged: _toggleShake,
          ),
          const Divider(),
          Text('Helplines (tap to call)', style: Theme.of(context).textTheme.titleMedium),
          for (final h in helplines)
            ListTile(
              dense: true,
              leading: const Icon(Icons.phone),
              title: Text(h.label),
              trailing: Text(h.number, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => _call(h.number),
            ),
          const Divider(),
          Text('Recent alerts', style: Theme.of(context).textTheme.titleMedium),
          if (_events.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('None yet.')),
          for (final e in _events)
            ListTile(
              dense: true,
              leading: Icon(e.delivered ? Icons.check_circle : Icons.schedule,
                  color: e.delivered ? Colors.green : Colors.orange),
              title: Text('${e.source.toUpperCase()}  ${e.time.toString().substring(0, 16)}'),
              subtitle: Text(e.lat == null
                  ? 'No location'
                  : '${e.lat!.toStringAsFixed(5)}, ${e.lng!.toStringAsFixed(5)}'),
            ),
        ],
      ),
    );
  }
}

class _CountdownDialog extends StatefulWidget {
  const _CountdownDialog();

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  int _left = 5;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
        Navigator.of(context).pop(true);
      } else {
        HapticFeedback.mediumImpact();
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sending SOS'),
      content: Text('Alerting your contacts in $_left...', style: const TextStyle(fontSize: 20)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('SEND NOW')),
      ],
    );
  }
}
