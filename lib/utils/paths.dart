import 'dart:io';

/// Caminhos de persistencia usados pelo bot (log e modelo ML).
///
/// Centralizados aqui para nao ficarem espalhados/hardcoded em varios pontos.
/// Em Android usa-se o Download publico (acessivel via Termux/adb); quando o
/// caminho nao esta disponivel, cai para um caminho local seguro.
class AppPaths {
  AppPaths._();

  static Directory get _base {
    const external = '/storage/emulated/0/Download';
    if (FileSystemEntity.typeSync(external) != FileSystemEntityType.notFound) {
      return Directory(external);
    }
    return Directory.systemTemp;
  }

  static File get logFile =>
      File('${_base.path}${Platform.pathSeparator}deriv_bot.log');

  static File get modelFile =>
      File('${_base.path}${Platform.pathSeparator}deriv_bot_model.json');

  /// Adiciona uma linha ao log de diagnostico (silenciosamente ignora falhas).
  static void appendLog(String line) {
    try {
      final ts = DateTime.now().toIso8601String().substring(11, 19);
      logFile.writeAsStringSync('[$ts] $line\n',
          mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
