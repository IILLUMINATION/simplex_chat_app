import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vthumb;

import '../../../../localization/app_localizations.dart';
import '../../models/chat_message_models.dart';
import '../../utils/chat_message_parser.dart';

class CircleRecorderScreen extends StatefulWidget {
  const CircleRecorderScreen({super.key});

  @override
  State<CircleRecorderScreen> createState() => _CircleRecorderScreenState();
}

class _CircleRecorderScreenState extends State<CircleRecorderScreen> {
  CameraController? _controller;
  bool _loading = true;
  bool _recording = false;
  int _elapsedSec = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _elapsedSec = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSec += 1);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _toggleRecording() async {
    final loc = AppLocalizations.of(context);
    final ctrl = _controller;
    if (ctrl == null || _loading) return;
    if (_recording) {
      final file = await ctrl.stopVideoRecording();
      _stopTimer();
      setState(() => _recording = false);
      final duration = _elapsedSec;
      final thumb = await (() async {
        try {
          return await vthumb.VideoThumbnail.thumbnailData(
            video: file.path,
            imageFormat: vthumb.ImageFormat.JPEG,
            maxWidth: 480,
            quality: 75,
          );
        } catch (_) {
          return null;
        }
      })();
      if (!mounted) return;
      if (thumb == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.translate('preview_error'))));
        return;
      }
      final previewBytes = prepareCirclePreview(thumb);
      Navigator.of(context).pop(
        CircleVideoResult(
          filePath: file.path,
          previewBytes: previewBytes,
          durationSec: duration,
        ),
      );
    } else {
      await ctrl.startVideoRecording();
      setState(() => _recording = true);
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final previewSize = _controller?.value.previewSize;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(loc.translate('circle')),
        actions: [
          if (_recording)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  formatDuration(_elapsedSec),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
        ],
      ),
      body: _loading || _controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Spacer(),
                Center(
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _recording
                            ? Colors.redAccent
                            : theme.colorScheme.outline,
                        width: 3,
                      ),
                    ),
                    child: ClipOval(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: previewSize?.height ?? 480,
                          height: previewSize?.width ?? 640,
                          child: CameraPreview(_controller!),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: GestureDetector(
                    onTap: _toggleRecording,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: _recording ? Colors.redAccent : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _recording ? Icons.stop : Icons.fiber_manual_record,
                        color: _recording ? Colors.white : Colors.redAccent,
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
