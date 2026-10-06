import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'vin_validator.dart';

/// Native camera scanner screen for Vehicle Identification Numbers (VIN).
/// Features real-time AUTO-CAPTURE for both printed VIN text (OCR) and VIN barcodes.
class VinScannerScreen extends StatefulWidget {
  const VinScannerScreen({super.key});

  /// Helper to route to the VIN scanner screen and return the confirmed VIN string.
  static Future<String?> start(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const VinScannerScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<VinScannerScreen> createState() => _VinScannerScreenState();
}

class _VinScannerScreenState extends State<VinScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  late final TextRecognizer _textRecognizer;
  late final BarcodeScanner _barcodeScanner;

  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  bool _hasPermissionError = false;
  bool _isTorchOn = false;
  String? _errorMessage;
  String? _detectedVin;

  static const Color _kNavy = Color(0xFF1F2E63);
  static const Color _kRed = Color(0xFFE01F26);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _barcodeScanner = BarcodeScanner();

    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textRecognizer.close();
    _barcodeScanner.close();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) setState(() => _hasPermissionError = true);
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _errorMessage = 'No camera found on this device.');
        }
        return;
      }

      final rearCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraDescription = rearCamera;

      final controller = CameraController(
        rearCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      _cameraController = controller;
      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _hasPermissionError = false;
        _errorMessage = null;
      });

      await controller.startImageStream(_processCameraFrame);
    } catch (error) {
      debugPrint('Camera initialization error: $error');
      if (mounted) {
        if (error is CameraException &&
            (error.code == 'CameraAccessDenied' ||
                error.code == 'CameraAccessRestricted')) {
          setState(() => _hasPermissionError = true);
        } else {
          setState(() => _errorMessage = 'Camera initialization failed: $error');
        }
      }
    }
  }

  /// Live real-time frame processing for automatic detection of barcodes and OCR text.
  Future<void> _processCameraFrame(CameraImage image) async {
    // Skip if already processing a previous frame or if a VIN has been detected
    if (_isProcessingFrame || _detectedVin != null || !mounted) return;
    _isProcessingFrame = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      // 1. Fast barcode detection
      final barcodes = await _barcodeScanner.processImage(inputImage);
      for (final barcode in barcodes) {
        final raw = barcode.rawValue ?? barcode.displayValue;
        if (raw != null && raw.isNotEmpty) {
          final vin = VinValidator.extractAndNormalize(raw);
          if (vin != null) {
            debugPrint('Auto-captured VIN from barcode: $vin');
            _onVinDetected(vin);
            return;
          }
        }
      }

      // 2. Real-time OCR text recognition (for printed VIN letters & numbers)
      final recognizedText = await _textRecognizer.processImage(inputImage);
      if (recognizedText.text.isNotEmpty) {
        final vin = VinValidator.extractFromOcrText(recognizedText.text);
        if (vin != null) {
          debugPrint('Auto-captured VIN from OCR text: $vin');
          _onVinDetected(vin);
          return;
        }
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameraDescription;
    if (camera == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation =
        InputImageRotationValue.fromRawValue(sensorOrientation);
    rotation ??= InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    final inputImageFormat = format ??
        (Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888);

    if (image.planes.isEmpty) return null;

    Uint8List bytes;
    if (Platform.isAndroid && image.planes.length > 1) {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      bytes = allBytes.done().buffer.asUint8List();
    } else {
      bytes = image.planes[0].bytes;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  void _onVinDetected(String vin) {
    if (!mounted || _detectedVin != null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _detectedVin = vin;
    });
  }

  void _onScanAgain() {
    if (!mounted) return;
    setState(() {
      _detectedVin = null;
      _isProcessingFrame = false;
    });
  }

  void _onUseVin() {
    if (_detectedVin != null) {
      Navigator.of(context).pop(_detectedVin);
    }
  }

  void _onClose() {
    Navigator.of(context).pop(null);
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final newMode = _isTorchOn ? FlashMode.off : FlashMode.torch;
      await controller.setFlashMode(newMode);
      if (mounted) {
        setState(() => _isTorchOn = !_isTorchOn);
      }
    } catch (e) {
      debugPrint('Failed to toggle torch: $e');
    }
  }

  Future<void> _requestPermissionAgain() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      setState(() {
        _hasPermissionError = false;
        _errorMessage = null;
      });
      unawaited(_initializeCamera());
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final scanWindowWidth = (mediaQuery.size.width * 0.88).clamp(260.0, 420.0);
    const scanWindowHeight = 150.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Preview
          if (_isCameraInitialized &&
              _cameraController != null &&
              !_hasPermissionError &&
              _errorMessage == null)
            ClipRect(
              child: SizedOverflowBox(
                size: mediaQuery.size,
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize?.height ??
                        mediaQuery.size.width,
                    height: _cameraController!.value.previewSize?.width ??
                        mediaQuery.size.height,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
            )
          else if (!_hasPermissionError && _errorMessage == null)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Custom Viewfinder Overlay
          if (!_hasPermissionError && _errorMessage == null)
            CustomPaint(
              painter: _ViewfinderOverlayPainter(
                windowWidth: scanWindowWidth,
                windowHeight: scanWindowHeight,
                overlayColor: Colors.black.withValues(alpha: 0.65),
                borderColor: _detectedVin != null ? Colors.greenAccent : _kRed,
              ),
            ),

          // Top Controls (Close, Title, Torch)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close button
                    _CircleIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Close scanner',
                      onPressed: _onClose,
                    ),
                    // Title badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.amberAccent,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'VIN Auto-Scanner',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Flashlight toggle
                    _CircleIconButton(
                      icon: _isTorchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      tooltip: _isTorchOn ? 'Turn off flash' : 'Turn on flash',
                      iconColor: _isTorchOn ? Colors.amberAccent : Colors.white,
                      onPressed: _toggleTorch,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Live Auto-Detection Guidance
          if (!_hasPermissionError &&
              _errorMessage == null &&
              _detectedVin == null)
            Positioned(
              left: 20,
              right: 20,
              bottom: mediaQuery.padding.bottom + 40,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.greenAccent,
                        ),
                      ),
                      SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Position the VIN or VIN barcode inside the frame',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Error / Permission Denied UI
          if (_hasPermissionError || _errorMessage != null)
            _buildErrorOverlay(context),

          // Confirmation Bottom Sheet (When VIN Detected)
          if (_detectedVin != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildVinConfirmationSheet(context, _detectedVin!),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorOverlay(BuildContext context) {
    final isPermission = _hasPermissionError;
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPermission
                  ? Icons.no_photography_rounded
                  : Icons.error_outline_rounded,
              size: 56,
              color: _kRed,
            ),
            const SizedBox(height: 18),
            Text(
              isPermission ? 'Camera Permission Required' : 'Camera Error',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              isPermission
                  ? 'DayDispatch requires camera permission to scan vehicle VIN numbers. Please grant access in device settings.'
                  : (_errorMessage ?? 'Unable to start camera scanner.'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                if (isPermission) ...[
                  const SizedBox(width: 14),
                  ElevatedButton(
                    onPressed: _requestPermissionAgain,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Grant Access'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVinConfirmationSheet(BuildContext context, String vin) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF2E7D32),
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                'VIN Detected',
                style: TextStyle(
                  color: Color(0xFF1F2E63),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Scanned VIN Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E3EB)),
            ),
            child: SelectableText(
              vin,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                color: Color(0xFF1F2E63),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Buttons: Use VIN & Scan Again
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _onScanAgain,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1F2E63),
                    side: const BorderSide(color: Color(0xFF1F2E63), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Scan Again',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ElevatedButton(
                  onPressed: _onUseVin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kNavy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Use VIN',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: Icon(icon, color: iconColor, size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

class _ViewfinderOverlayPainter extends CustomPainter {
  _ViewfinderOverlayPainter({
    required this.windowWidth,
    required this.windowHeight,
    required this.overlayColor,
    required this.borderColor,
  });

  final double windowWidth;
  final double windowHeight;
  final Color overlayColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(
      center: center,
      width: windowWidth,
      height: windowHeight,
    );
    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(14));

    // Dark semi-transparent background with cut-out hole
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rRect)
      ..fillType = PathFillType.evenOdd;

    final backgroundPaint = Paint()..color = overlayColor;
    canvas.drawPath(backgroundPath, backgroundPaint);

    // Border around scan area
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(rRect, borderPaint);

    // Accent corner brackets
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    const cornerLength = 22.0;

    // Top-Left
    canvas.drawLine(
      Offset(rect.left, rect.top + cornerLength),
      Offset(rect.left, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left + cornerLength, rect.top),
      cornerPaint,
    );

    // Top-Right
    canvas.drawLine(
      Offset(rect.right - cornerLength, rect.top),
      Offset(rect.right, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.top + cornerLength),
      cornerPaint,
    );

    // Bottom-Left
    canvas.drawLine(
      Offset(rect.left, rect.bottom - cornerLength),
      Offset(rect.left, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left + cornerLength, rect.bottom),
      cornerPaint,
    );

    // Bottom-Right
    canvas.drawLine(
      Offset(rect.right - cornerLength, rect.bottom),
      Offset(rect.right, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right, rect.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ViewfinderOverlayPainter oldDelegate) {
    return oldDelegate.windowWidth != windowWidth ||
        oldDelegate.windowHeight != windowHeight ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.borderColor != borderColor;
  }
}
