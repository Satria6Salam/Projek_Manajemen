import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/utils/name_repairer.dart';
import 'data/repositories/repository_provider.dart';
import 'features/auth/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pilih implementasi repository: FastAPI (default) atau lokal/demo.
  // Lihat lib/core/constants/app_config.dart (useFastApi).
  AppRepositories.init();

  final session = SessionController(AppRepositories.instance.auth);
  // Jika token tidak bisa diperpanjang, kembalikan pengguna ke layar Login.
  AppRepositories.instance.client?.onSessionExpired = session.expire;
  runApp(StrukkuApp(session: session));
  // Kosakata perbaikan ejaan offline dimuat di latar belakang (tidak menahan start-up).
  _loadNameRepairer();
}

Future<void> _loadNameRepairer() async {
  try {
    final text = await rootBundle.loadString('assets/data/vocabulary.txt');
    NameRepairer.instance = await compute(NameRepairer.fromText, text);
  } catch (e) {
    debugPrint('[STRUKKU] kosakata offline gagal dimuat: $e');
  }
}
