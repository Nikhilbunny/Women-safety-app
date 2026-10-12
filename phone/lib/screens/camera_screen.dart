import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

/// Record video evidence with the back or front camera.
/// Recording is always visible on screen and only starts when you press the button.
/// Videos are saved on this phone; you choose if and where to share them.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  List<CameraDescription> _cams = [];
  CameraController? _ctl;
  int _index = 0;
  bool _recording = false;
  bool _busy = false;
  String? _error;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      setState(() => _error = 'Camera and microphone permission are needed to record. '
          'Allow them in Settings, then open this screen again.');
      return;
    }
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        setState(() => _error = 'No camera found on this phone.');
        return;
      }
      final back = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      await _open(back >= 0 ? back : 0);
    } catch (e) {
      setState(() => _error = 'Could not start the camera.');
    }
  }

  Future<void> _open(int index) async {
    final old = _ctl;
    final c = CameraController(_cams[index], ResolutionPreset.high, enableAudio: true);
    setState(() {
      _ctl = null;
      _index = index;
    });
    await old?.dispose();
    try {
      await c.initialize();
    } catch (e) {
      setState(() => _error = 'Could not start the camera.');
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _ctl = c);
  }

  bool get _isFront => _cams.isNotEmpty && _cams[_index].lensDirection == CameraLensDirection.front;

  Future<void> _switchCamera() async {
    if (_recording || _busy || _cams.length < 2) return;
    final wantFront = !_isFront;
    final target = _cams.indexWhere((c) =>
        c.lensDirection == (wantFront ? CameraLensDirection.front : CameraLensDirection.back));
    if (target >= 0) await _open(target);
  }

  Future<Directory> _recordingsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/recordings');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _toggleRecording() async {
    final c = _ctl;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (_recording) {
        final file = await c.stopVideoRecording();
        _timer?.cancel();
        final dir = await _recordingsDir();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final target = '${dir.path}/rec_${stamp}_${_isFront ? 'front' : 'back'}.mp4';
        await File(file.path).copy(target);
        try {
          await File(file.path).delete();
        } catch (_) {}
        if (mounted) {
          setState(() => _recording = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved. Open the list at the top right to share it.')),
          );
        }
      } else {
        await c.startVideoRecording();
        _elapsed = Duration.zero;
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
        });
        setState(() => _recording = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording failed. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctl;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Record evidence'),
        actions: [
          IconButton(
            tooltip: 'Saved recordings',
            icon: const Icon(Icons.video_library),
            onPressed: _recording
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RecordingsScreen()),
                    ),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              ),
            )
          : c == null || !c.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Center(child: CameraPreview(c)),
                          if (_recording)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.shade700,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'REC  ${_fmt(_elapsed)}  ${_isFront ? 'front' : 'back'} camera',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              iconSize: 32,
                              color: Colors.white,
                              tooltip: _isFront ? 'Use back camera' : 'Use front camera',
                              icon: const Icon(Icons.cameraswitch),
                              onPressed: (_recording || _cams.length < 2) ? null : _switchCamera,
                            ),
                            GestureDetector(
                              onTap: _toggleRecording,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 4),
                                ),
                                alignment: Alignment.center,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: _recording ? 28 : 56,
                                  height: _recording ? 28 : 56,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(_recording ? 6 : 28),
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _isFront ? 'FRONT' : 'BACK',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Saved recordings, newest first. Share or delete.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<FileSystemEntity> _files = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/recordings');
    var files = <FileSystemEntity>[];
    if (await dir.exists()) {
      files = dir.listSync().where((f) => f.path.endsWith('.mp4')).toList();
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    }
    if (!mounted) return;
    setState(() {
      _files = files;
      _loaded = true;
    });
  }

  String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).round()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Future<void> _delete(FileSystemEntity f) async {
    await f.delete();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved recordings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('No recordings yet.'))
              : ListView(
                  children: [
                    for (final f in _files)
                      ListTile(
                        leading: const Icon(Icons.movie),
                        title: Text(f.statSync().modified.toString().substring(0, 16)),
                        subtitle: Text(
                          '${f.path.contains('_front') ? 'Front' : 'Back'} camera  -  ${_size(f.statSync().size)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Share',
                              icon: const Icon(Icons.share),
                              onPressed: () => Share.shareXFiles([XFile(f.path)]),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(f),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}
