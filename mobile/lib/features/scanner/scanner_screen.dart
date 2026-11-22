import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/receipt_parser.dart';
import '../../core/widgets/state_views.dart';
import '../../data/local/demo_data.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/receipt_model.dart';
import '../../models/user_model.dart';
import '../../navigation/app_router.dart';
import 'image_enhancement_service.dart';
import 'ocr_service.dart';
import 'receipt_selector.dart';
import 'scan_result.dart';
import 'steadiness_tracker.dart';

/// Halaman Pindai Struk: kamera + bingkai, galeri, OCR, lalu ke validasi.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.user});

  final UserModel user;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final OcrService _ocr = OcrService();
  final ImageEnhancementService _enhancer = ImageEnhancementService();
  static const ReceiptSelector _selector = ReceiptSelector();

  CameraController? _controller;
  bool _initializing = true;
  String? _cameraError;
  bool _torchOn = false;

  XFile? _captured;
  bool _processing = false;

  // Kestabilan HP: foto goyang berat tidak bisa diperbaiki, jadi dicegah sejak memotret.
  final SteadinessTracker _steady = SteadinessTracker();
  StreamSubscription<UserAccelerometerEvent>? _motionSub;
  bool _motionAvailable = false;
  bool _wasSteady = false;
  bool _autoCapture = false;
  bool _autoFired = false;
  DateTime _lastMotionUi = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _autoCaptureAfter = Duration(milliseconds: 1200);
  String _processingLabel = '';

  // Pindai banyak struk dari galeri: diproses satu per satu.
  List<XFile> _batch = const [];
  int _batchIndex = 0;
  int _batchSaved = 0;

  bool get _inBatch => _batch.length > 1;
  String get _batchPrefix =>
      _inBatch ? 'Struk ${_batchIndex + 1} dari ${_batch.length}: ' : '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _startMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motionSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startMotion() {
    try {
      _motionSub = userAccelerometerEventStream(
              samplingPeriod: SensorInterval.uiInterval)
          .listen(_onMotion, onError: (_) {
        if (mounted) setState(() => _motionAvailable = false);
      }, cancelOnError: true);
    } catch (_) {
      _motionAvailable = false; // sensor tidak ada: kamera tetap jalan normal
    }
  }

  void _onMotion(UserAccelerometerEvent e) {
    final now = DateTime.now();
    _steady.add(e.x, e.y, e.z, now);
    if (!mounted) return;
    final steady = _steady.isSteady;
    final cameraLive = _controller != null && _captured == null && !_processing;
    if (_autoCapture &&
        !_autoFired &&
        cameraLive &&
        _steady.steadyFor(now) >= _autoCaptureAfter) {
      _autoFired = true;
      _capture();
    }
    // Perbarui indikator saat status berubah, atau paling sering 4x per detik.
    if (!_motionAvailable ||
        steady != _wasSteady ||
        now.difference(_lastMotionUi) > const Duration(milliseconds: 250)) {
      _lastMotionUi = now;
      setState(() {
        _motionAvailable = true;
        _wasSteady = steady;
      });
    }
  }

  /// Setelah memotret: bila foto sangat buram/goyang atau terlalu gelap,
  /// sarankan foto ulang (lebih baik daripada hasil baca yang salah).
  Future<void> _checkCaptureQuality(XFile file) async {
    final quality = await _enhancer.assess(file.path);
    if (quality == null || !mounted || _captured?.path != file.path) return;
    final verdict = CaptureVerdict.judge(
      blurLevel: quality.blurLevel,
      isDark: quality.isDark,
      brightness: quality.brightness,
      glareRatio: quality.glareRatio,
      paperFill: quality.paperFill,
    );
    if (!verdict.retake) return;
    if (verdict.mustRetake) {
      await _forceRetakeDialog(verdict.reasons);
      return;
    }
    final retake = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto kurang jelas'),
        content: Text(
          'Terdeteksi: ${verdict.reasons.join(', ')}. Hasil baca struk bisa salah.\n\n'
          'Tips: tahan HP diam sampai indikator hijau, pastikan cahaya cukup '
          '(nyalakan flash bila perlu, tapi miringkan HP sedikit bila ada pantulan), '
          'dan dekatkan HP sampai struk memenuhi bingkai.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tetap pakai')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Foto ulang')),
        ],
      ),
    );
    if (retake == true && mounted) _retake();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lepas kamera saat aplikasi di latar belakang, nyalakan lagi saat kembali.
    if (state == AppLifecycleState.inactive) {
      final c = _controller;
      if (c != null && mounted) {
        // Lepas dari UI dulu agar CameraPreview tidak memakai controller yang sudah dibuang.
        setState(() => _controller = null);
        c.dispose();
      }
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        _captured == null &&
        !_processing) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cameraError = 'Kamera tidak tersedia di perangkat ini. '
              'Kamu tetap bisa memilih gambar struk dari galeri.';
          _initializing = false;
        });
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller =
          CameraController(camera, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _torchOn = false;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.startsWith('CameraAccess');
      setState(() {
        _cameraError = denied
            ? 'Izin kamera ditolak. Aktifkan izin kamera di Pengaturan, '
                'atau pilih gambar struk dari galeri.'
            : 'Kamera tidak dapat dibuka (${e.description ?? e.code}). '
                'Kamu bisa memilih gambar dari galeri.';
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError =
            'Kamera tidak dapat dibuka. Kamu bisa memilih gambar dari galeri.';
        _initializing = false;
      });
    }
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      setState(() => _torchOn = !_torchOn);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Flash tidak tersedia di perangkat ini.',
            error: true);
      }
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
    try {
      final file = await c.takePicture();
      if (_torchOn) {
        await c.setFlashMode(FlashMode.off);
        _torchOn = false;
      }
      if (mounted) {
        setState(() => _captured = file);
        unawaited(_checkCaptureQuality(file));
      }
    } on CameraException catch (e) {
      if (mounted) {
        showAppSnackBar(
            context, 'Gagal mengambil foto: ${e.description ?? e.code}',
            error: true);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      // Boleh memilih beberapa foto struk sekaligus.
      final files = await _picker.pickMultiImage();
      if (files.isEmpty || !mounted) return;
      if (files.length == 1) {
        setState(() => _captured = files.first);
        unawaited(_checkCaptureQuality(files.first));
        return;
      }
      setState(() {
        _batch = files;
        _batchIndex = 0;
        _batchSaved = 0;
        _captured = files.first;
      });
      await _useCaptured();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Galeri tidak dapat dibuka: $e', error: true);
      }
    }
  }

  void _retake() {
    _autoFired = false;
    _steady.reset();
    setState(() => _captured = null);
    if (_controller == null) _initCamera();
  }

  // --------------------------------------------------------------------------
  // Proses: OCR -> parsing -> klasifikasi -> halaman validasi
  // --------------------------------------------------------------------------

  /// Foto terlalu buram/gelap untuk dibaca: tidak diproses, minta foto ulang.
  Future<void> _forceRetakeDialog(List<String> reasons) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto buram, silakan foto ulang'),
        content: Text(
          'Terdeteksi: ${reasons.join(', ')}. Tulisan tidak bisa dibaca dengan benar '
          '(tanggal, harga, dan total bisa salah).\n\n'
          'Tahan HP diam sampai indikator hijau, pastikan cahaya cukup, '
          'dan dekatkan HP sampai struk memenuhi bingkai.',
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Foto ulang')),
        ],
      ),
    );
    if (mounted) _retake();
  }

  /// Hasil baca tanpa tanggal/total dari foto yang agak buram: tawarkan foto ulang.
  Future<bool> _offerRetakeForMissing(ParsedReceipt parsed, String path) async {
    final missing = <String>[
      if (parsed.transactionDate == null) 'tanggal',
      if (parsed.totalAmount == null) 'total',
    ];
    if (missing.isEmpty || _inBatch) return false;
    final quality = await _enhancer.assess(path);
    if (quality == null || !mounted) return false;
    if (!quality.isBlurry && !quality.isDark && !quality.isFaded) return false;
    final retake = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sebagian data tidak terbaca'),
        content: Text(
          '${missing.join(' dan ')} tidak terbaca karena ${quality.notes.join(', ')}. '
          'Foto ulang agar hasilnya lengkap?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Isi manual')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Foto ulang')),
        ],
      ),
    );
    if (retake == true && mounted) {
      setState(() => _processing = false);
      _retake();
      return true;
    }
    return false;
  }

  Future<void> _useCaptured() async {
    final path = _captured?.path;
    if (path == null) return;

    // Foto terlalu buram: jangan dibaca (hasilnya pasti salah), minta foto ulang.
    if (!_inBatch) {
      final quality = await _enhancer.assess(path);
      if (!mounted) return;
      if (quality != null) {
        final verdict = CaptureVerdict.judge(
          blurLevel: quality.blurLevel,
          isDark: quality.isDark,
          brightness: quality.brightness,
          glareRatio: quality.glareRatio,
          paperFill: quality.paperFill,
        );
        if (verdict.mustRetake) {
          await _forceRetakeDialog(verdict.reasons);
          return;
        }
      }
    }

    setState(() {
      _processing = true;
      _processingLabel = _batchPrefix +
          (AppConfig.useFastApi
              ? 'Mengirim struk ke server...'
              : 'Membaca teks struk...');
    });

    // 1. Mode server: OCR Tesseract bertingkat + parser lengkap (qty, harga
    //    satuan) + kategori, dan foto tersimpan di server. Teks ML Kit dari HP
    //    ikut dikirim agar server memilih bacaan yang paling konsisten dari
    //    dua mesin OCR. Bila server tidak terjangkau atau tidak bisa membaca
    //    struk, lanjut ke OCR di HP.
    String? deviceText;
    if (AppConfig.useFastApi) {
      try {
        deviceText =
            await _ocr.recognize(path).timeout(const Duration(seconds: 8));
      } catch (_) {
        deviceText = null; // ML Kit gagal: server tetap memakai Tesseract.
      }
      if (!mounted) return;
    }
    final ServerScan? server = await _tryServerScan(path, deviceText);
    if (!mounted) return;
    if (server != null) {
      if (await _offerRetakeForMissing(server.parsed, path)) return;
      await _goToValidation(
        imagePath: path,
        rawText: server.rawText,
        parsed: server.parsed,
        classification: server.classification,
        scanId: server.scanId,
        warnings: server.warnings,
        consistent: server.consistent,
        reviewFields: server.reviewFields,
      );
      return;
    }
    setState(() => _processingLabel = 'Membaca teks struk di HP...');

    ReceiptReading? reading;
    Object? firstError;
    try {
      final String text = await _ocr.recognize(path);
      reading =
          ReceiptReading(rawText: text, parsed: ReceiptParser.parse(text));
    } catch (e) {
      firstError = e;
    }

    // Hasil belum lengkap (foto buram/gelap/pudar): perjelas foto, baca ulang,
    // lalu pilih hasil terbaik. Bila masih kurang, coba sekali lagi dengan
    // penajaman lebih kuat.
    List<String> qualityNotes = const <String>[];
    for (final bool strong in <bool>[false, true]) {
      if (reading != null && _selector.isComplete(reading.parsed)) break;
      if (strong && (reading == null || qualityNotes.isEmpty)) break;
      if (!mounted) return;
      setState(() => _processingLabel =
          strong ? 'Mempertajam foto buram...' : 'Memperjelas foto struk...');
      final EnhancedImage? enhanced =
          await _enhancer.enhance(path, forceSharpen: strong);
      if (enhanced == null) break;
      qualityNotes = enhanced.quality.notes;
      try {
        final String text = await _ocr.recognize(enhanced.path);
        final ReceiptReading second = ReceiptReading(
          rawText: text,
          parsed: ReceiptParser.parse(text),
          fromEnhancedImage: true,
        );
        reading = reading == null ? second : _selector.choose(reading, second);
      } catch (_) {
        // Bacaan ulang gagal: tetap pakai hasil dari foto asli.
      } finally {
        await _enhancer.discard(enhanced);
      }
    }

    if (!mounted) return;
    if (reading == null) {
      setState(() => _processing = false);
      _showOcrFailedDialog(
          'Pembacaan teks gagal. Pastikan struk terang dan tidak buram.\n($firstError)');
      return;
    }
    if (reading.parsed.isEmpty) {
      setState(() => _processing = false);
      _showOcrFailedDialog('Teks pada gambar tidak terbaca sebagai struk'
          '${qualityNotes.isEmpty ? '' : ' (${qualityNotes.join(', ')})'}. '
          'Coba foto ulang dengan pencahayaan lebih baik dan kamera tidak bergerak, '
          'atau isi data secara manual.');
      return;
    }
    if (await _offerRetakeForMissing(reading.parsed, path)) return;
    if (!mounted) return;
    await _goToValidation(
      imagePath: path,
      rawText: reading.rawText,
      parsed: reading.parsed,
      qualityNotes: qualityNotes,
      enhanced: reading.fromEnhancedImage,
    );
  }

  /// Pindai di server. null = tidak dipakai (mode demo), gagal, atau tidak
  /// terbaca, sehingga pemanggil memakai OCR di HP.
  Future<ServerScan?> _tryServerScan(String path, String? deviceText) async {
    try {
      final ServerScan? scan = await AppRepositories.instance.receipts
          .scanReceipt(path, deviceText: deviceText);
      if (scan == null || scan.parsed.isEmpty) return null;
      return scan;
    } on AppException catch (e) {
      debugPrint(
          '[STRUKKU] pindai server gagal (${e.code ?? e.statusCode}): ${e.message}');
      if (mounted && e.code != 'OCR_EMPTY') {
        showAppSnackBar(context,
            'Server tidak dapat memindai (${e.message}). Memakai pembaca teks di HP.');
      }
      return null;
    } catch (e) {
      debugPrint('[STRUKKU] pindai server gagal: $e');
      return null;
    }
  }

  Future<void> _goToValidation({
    required String? imagePath,
    required String rawText,
    required ParsedReceipt parsed,
    bool isDemoSample = false,
    List<String> qualityNotes = const <String>[],
    bool enhanced = false,
    ClassificationResult? classification,
    String? scanId,
    List<String> warnings = const <String>[],
    bool? consistent,
    List<String> reviewFields = const <String>[],
  }) async {
    setState(() {
      _processing = true;
      _processingLabel = 'Mengklasifikasikan barang...';
    });

    if (classification == null && parsed.items.isNotEmpty) {
      try {
        classification = await AppRepositories.instance.receipts
            .classifyItems(parsed.items.map((i) => i.name).toList());
      } on AppException catch (e) {
        if (mounted) {
          showAppSnackBar(context,
              'Klasifikasi gagal: ${e.message}. Pilih kategori secara manual.',
              error: true);
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(
              context, 'Klasifikasi gagal: $e. Pilih kategori secara manual.',
              error: true);
        }
      }
    }
    if (!mounted) return;
    setState(() => _processing = false);

    // Catatan: tanpa parameter tipe <ReceiptModel>. AppRouter membuat
    // MaterialPageRoute<dynamic>, sehingga pushNamed<ReceiptModel> memicu
    // error tipe dan halaman validasi tidak pernah terbuka.
    debugPrint(
        '[STRUKKU] buka halaman validasi: ${parsed.items.length} barang, '
        'total=${parsed.totalAmount}, klasifikasi=${classification?.predictions.length}');
    Object? result;
    try {
      result = await Navigator.pushNamed(
        context,
        AppRoutes.validation,
        arguments: ValidationArgs(
          user: widget.user,
          scan: ScanResult(
            imagePath: imagePath,
            rawText: rawText,
            parsed: parsed,
            classification: classification,
            isDemoSample: isDemoSample,
            qualityNotes: qualityNotes,
            enhanced: enhanced,
            scanId: scanId,
            warnings: warnings,
            consistent: consistent,
            reviewFields: reviewFields,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[STRUKKU] gagal membuka halaman validasi: $e\n$st');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Halaman validasi gagal dibuka'),
          content: SingleChildScrollView(child: Text('$e')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup')),
          ],
        ),
      );
      return;
    }
    debugPrint(
        '[STRUKKU] kembali dari halaman validasi: ${result.runtimeType}');

    // Jika struk tersimpan, tutup halaman pindai dan kembali ke Beranda.
    if (!mounted) return;
    if (_inBatch) {
      if (result is ReceiptModel) _batchSaved++;
      await _nextInBatch();
      return;
    }
    if (result is ReceiptModel) Navigator.pop(context, result);
  }

  /// Lanjut ke foto berikutnya dalam antrean; selesai -> kembali ke Beranda.
  Future<void> _nextInBatch({String? skippedReason}) async {
    if (skippedReason != null && mounted) {
      showAppSnackBar(context, '${_batchPrefix}dilewati ($skippedReason).',
          error: true);
    }
    if (_batchIndex + 1 >= _batch.length) {
      final saved = _batchSaved;
      final total = _batch.length;
      setState(() {
        _batch = const [];
        _processing = false;
        _captured = null;
      });
      if (!mounted) return;
      showAppSnackBar(context, '$saved dari $total struk tersimpan.');
      Navigator.pop(context);
      return;
    }
    setState(() {
      _batchIndex++;
      _captured = _batch[_batchIndex];
    });
    await _useCaptured();
  }

  void _showOcrFailedDialog(String message) {
    if (_inBatch) {
      _nextInBatch(skippedReason: 'teks tidak terbaca');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Struk belum terbaca'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _retake();
            },
            child: const Text('Ulangi'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _goToValidation(
                  imagePath: _captured?.path,
                  rawText: '',
                  parsed: const ParsedReceipt());
            },
            child: const Text('Isi Manual'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _goToValidation(
                imagePath: _captured?.path,
                rawText: DemoData.sampleReceiptText,
                parsed: ReceiptParser.parse(DemoData.sampleReceiptText),
                isDemoSample: true,
              );
            },
            child: const Text('Pakai Contoh Demo'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scannerEdge,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [AppColors.scannerCenter, AppColors.scannerEdge],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: _buildFrameArea()),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: _captured == null &&
                            _motionAvailable &&
                            _controller != null
                        ? _buildSteadyHint()
                        : Text(
                            _captured != null
                                ? 'Struk berhasil dipindai'
                                : 'Posisikan seluruh struk di dalam bingkai',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12.5),
                          ),
                  ),
                  _buildBottomBar(),
                  const SizedBox(height: 18),
                ],
              ),
              if (_processing)
                Positioned.fill(
                  child: Container(
                    color: const Color(0xB3000000),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 16),
                          Text(_processingLabel,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleAutoCapture() {
    setState(() {
      _autoCapture = !_autoCapture;
      _autoFired = false;
      _steady.reset();
    });
    showAppSnackBar(
        context,
        _autoCapture
            ? 'Foto otomatis aktif: tahan HP diam sampai indikator hijau.'
            : 'Foto otomatis dimatikan.');
  }

  /// Indikator kestabilan: hijau = siap foto, kuning = tahan HP diam.
  Widget _buildSteadyHint() {
    final steady = _steady.isSteady;
    final color = steady ? AppColors.scanGreen : const Color(0xFFFFB74D);
    final text = steady
        ? (_autoCapture
            ? 'HP diam \u2014 memotret otomatis...'
            : 'HP diam \u2014 siap memotret')
        : 'Tahan HP diam agar foto tidak buram';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(steady ? Icons.check_circle : Icons.pan_tool_alt_outlined,
            color: color, size: 16),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _circleButton(IconData icon, VoidCallback? onTap,
      {String? tooltip, Color? color}) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
              color: Color(0x33FFFFFF), shape: BoxShape.circle),
          child: Icon(icon, color: color ?? Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _circleButton(
              Icons.close, _processing ? null : () => Navigator.pop(context),
              tooltip: 'Tutup'),
          const Text('Pindai Struk',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          Row(
            children: [
              if (_motionAvailable) ...[
                _circleButton(
                  _autoCapture
                      ? Icons.motion_photos_auto
                      : Icons.motion_photos_off,
                  (_captured == null && !_processing)
                      ? _toggleAutoCapture
                      : null,
                  tooltip: 'Foto otomatis saat HP diam',
                  color: _autoCapture ? AppColors.scanGreen : Colors.white,
                ),
                const SizedBox(width: 10),
              ],
              _circleButton(
                _torchOn ? Icons.flash_on : Icons.flash_off,
                (_controller != null && _captured == null && !_processing)
                    ? _toggleTorch
                    : null,
                tooltip: 'Flash',
                color: _torchOn ? const Color(0xFFFFD54F) : Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFrameArea() {
    return LayoutBuilder(builder: (context, box) {
      final width = (box.maxWidth - 60).clamp(200.0, 340.0).toDouble();
      final height = (box.maxHeight - 16).clamp(200.0, 560.0).toDouble();

      Widget content;
      if (_captured != null) {
        content = Padding(
          padding: const EdgeInsets.all(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.scanGreen, width: 4),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Image.file(File(_captured!.path), fit: BoxFit.contain),
          ),
        );
      } else if (_initializing || _controller == null) {
        content =
            const Center(child: CircularProgressIndicator(color: Colors.white));
      } else if (_cameraError != null) {
        content = Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined,
                    color: Colors.white70, size: 44),
                const SizedBox(height: 12),
                Text(_cameraError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, height: 1.4)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Pilih dari Galeri'),
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(200, 46)),
                ),
                TextButton(
                  onPressed: _initCamera,
                  child: const Text('Coba buka kamera lagi',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        );
      } else {
        final c = _controller!;
        final size = c.value.previewSize;
        content = ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              // previewSize berorientasi landscape; tukar untuk potret.
              width: size?.height ?? 1,
              height: size?.width ?? 1,
              child: CameraPreview(c),
            ),
          ),
        );
      }

      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(6), child: content)),
              const Positioned.fill(
                  child: IgnorePointer(
                      child: CustomPaint(painter: _FramePainter()))),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildBottomBar() {
    final hasImage = _captured != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _squareButton(Icons.photo_library_outlined,
              _processing ? null : _pickFromGallery, 'Galeri'),
          if (hasImage)
            FilledButton(
              onPressed: _processing ? null : _useCaptured,
              style: FilledButton.styleFrom(
                minimumSize: const Size(150, 50),
                shape: const StadiumBorder(),
              ),
              child: const Text('Gunakan Foto'),
            )
          else
            GestureDetector(
              onTap: (_controller != null && !_processing) ? _capture : null,
              child: Container(
                width: 74,
                height: 74,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _controller != null ? Colors.white : Colors.white38,
                  ),
                ),
              ),
            ),
          _squareButton(
              Icons.refresh,
              _processing ? null : (hasImage ? _retake : _initCamera),
              hasImage ? 'Ulangi' : 'Muat ulang kamera'),
        ],
      ),
    );
  }

  Widget _squareButton(IconData icon, VoidCallback? onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// Empat sudut bingkai putih (area penempatan struk).
class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const len = 30.0;
    const r = 8.0;

    Path corner(double x, double y, double dx, double dy) => Path()
      ..moveTo(x, y + dy * len)
      ..lineTo(x, y + dy * r)
      ..quadraticBezierTo(x, y, x + dx * r, y)
      ..lineTo(x + dx * len, y);

    canvas.drawPath(corner(0, 0, 1, 1), paint);
    canvas.drawPath(corner(size.width, 0, -1, 1), paint);
    canvas.drawPath(corner(0, size.height, 1, -1), paint);
    canvas.drawPath(corner(size.width, size.height, -1, -1), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
