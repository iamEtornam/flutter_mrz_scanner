import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_mrz_scanner/src/camera_overlay.dart';
import 'package:mrz_parser/mrz_parser.dart';

/// MRZ scanner camera widget
class MRZScanner extends StatelessWidget {
  const MRZScanner({
    required this.onControllerCreated,
    this.withOverlay = false,
    Key? key,
  }) : super(key: key);

  /// Provides a controller for MRZ handling
  final void Function(MRZController controller) onControllerCreated;

  /// Displays MRZ scanner overlay
  final bool withOverlay;

  @override
  Widget build(BuildContext context) {
    final scanner = defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            viewType: 'mrzscanner',
            onPlatformViewCreated: (int id) => onPlatformViewCreated(id),
            creationParamsCodec: const StandardMessageCodec(),
          )
        : defaultTargetPlatform == TargetPlatform.android
            ? AndroidView(
                viewType: 'mrzscanner',
                onPlatformViewCreated: (int id) => onPlatformViewCreated(id),
                creationParamsCodec: const StandardMessageCodec(),
              )
            : Text('$defaultTargetPlatform is not supported by this plugin');
    return withOverlay ? CameraOverlay(child: scanner) : scanner;
  }

  void onPlatformViewCreated(int id) {
    final controller = MRZController._init(id);
    onControllerCreated(controller);
  }
}

/// Result containing both the parsed MRZ and the raw OCR text
class MRZScannerResult {
  MRZScannerResult({
    required this.mrz,
    required this.rawMrz,
    this.parsedMrz,
  });

  /// The extracted MRZ string
  final String mrz;

  /// The raw unprocessed OCR text
  final String rawMrz;

  /// The parsed MRZ object (if parsing was successful)
  final MRZResult? parsedMrz;
}

class MRZController {
  MRZController._init(int id) {
    _channel = MethodChannel('mrzscanner_$id');
    _channel.setMethodCallHandler(_platformCallHandler);
  }

  late final MethodChannel _channel;

  void Function(MRZResult mrz)? onParsed;

  /// New callback with both the processed MRZ and raw OCR text
  void Function(MRZScannerResult result)? onScanned;

  void Function(String text)? onError;

  void flashlightOn() {
    _channel.invokeMethod<void>('flashlightOn');
  }

  void flashlightOff() {
    _channel.invokeMethod<void>('flashlightOff');
  }

  Future<List<int>?> takePhoto({
    bool crop = true,
  }) async {
    final result = await _channel.invokeMethod<List<int>>('takePhoto', {
      'crop': crop,
    });
    return result;
  }

  Future<void> _platformCallHandler(MethodCall call) {
    switch (call.method) {
      case 'onError':
        onError?.call(call.arguments);
        break;
      case 'onParsed':
        if (onParsed != null || onScanned != null) {
          // Handle new response format (Map with 'mrz' and 'rawMrz')
          final Map<dynamic, dynamic>? resultMap =
              call.arguments is Map ? call.arguments : null;
          final String mrzText = resultMap != null && resultMap['mrz'] != null
              ? resultMap['mrz'] as String
              : call.arguments is String
                  ? call.arguments
                  : '';

          final String rawMrzText =
              resultMap != null && resultMap['rawMrz'] != null
                  ? resultMap['rawMrz'] as String
                  : mrzText;

          final lines = _splitRecognized(mrzText);
          MRZResult? parsedResult;

          if (lines.isNotEmpty) {
            parsedResult = MRZParser.tryParse(lines);
            if (parsedResult != null && onParsed != null) {
              onParsed!(parsedResult);
            }
          }

          if (onScanned != null) {
            onScanned!(MRZScannerResult(
              mrz: mrzText,
              rawMrz: rawMrzText,
              parsedMrz: parsedResult,
            ));
          }
        }
        break;
    }
    return Future.value();
  }

  List<String> _splitRecognized(String recognizedText) {
    final mrzString = recognizedText.replaceAll(' ', '');
    return mrzString.split('\n').where((s) => s.isNotEmpty).toList();
  }

  void startPreview({bool isFrontCam = false}) => _channel.invokeMethod<void>(
        'start',
        {
          'isFrontCam': isFrontCam,
        },
      );

  void stopPreview() => _channel.invokeMethod<void>('stop');
}
