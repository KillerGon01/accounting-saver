import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/reports/monthly_report.dart';
import '../../domain/reports/monthly_report_gateway.dart';
import '../../domain/transactions/llm_gateway_exception.dart';

/// Pide a la IA un comentario sobre un [MonthlyReport] ya calculado, con
/// el mismo tope de cuota que `SendChatMessage`: como mucho
/// [maxCommentsPerSession] llamadas con éxito por sesión (una instancia),
/// caché en memoria por mes (invalidada si cambian los movimientos) y
/// ninguna llamada simultánea.
///
/// No decide aquí qué hacer si el mes no tiene movimientos ("No hay
/// movimientos este mes"): eso ya lo sabe la pantalla a partir del
/// `MonthlyReport` que ya tiene, así que no necesita llamar a este caso
/// de uso para mostrarlo.
class ExplainMonthlyReport {
  ExplainMonthlyReport(this._gateway, [TransactionsChangeNotifier? changeNotifier])
    : _changeNotifier = changeNotifier ?? TransactionsChangeNotifier();

  /// Tope de comentarios generados con éxito por sesión (una instancia;
  /// ver el provider que la crea). Igual que en el chat, ni una respuesta
  /// servida desde la caché ni una que acaba en error (red, cuota, 503,
  /// timeout...) gastan una de las 3, porque ninguna de las dos cuesta
  /// cuota de verdad.
  static const maxCommentsPerSession = 3;

  final MonthlyReportGateway _gateway;
  final TransactionsChangeNotifier _changeNotifier;
  final _cache = <String, _CachedComment>{};

  bool _isGenerating = false;
  int _commentsGenerated = 0;

  /// Comentarios que quedan en esta sesión antes de llegar a
  /// [maxCommentsPerSession]. Nunca negativo.
  int get remainingComments => (maxCommentsPerSession - _commentsGenerated).clamp(0, maxCommentsPerSession);

  Future<String> call({required MonthlyReport report}) async {
    if (_isGenerating) {
      throw StateError('Ya hay una petición de comentario en curso.');
    }
    if (_commentsGenerated >= maxCommentsPerSession) {
      throw const LlmGatewayException(
        'comment-limit-reached',
        message: 'Has llegado al máximo de comentarios de esta sesión.',
      );
    }

    _isGenerating = true;
    try {
      final key = _cacheKey(report);
      final cached = _cache[key];
      if (cached != null && cached.transactionsVersion == _changeNotifier.version) {
        return cached.comment;
      }

      final comment = await _gateway.explain(report);

      // Solo se cuenta aquí, tras una llamada al modelo que ha terminado
      // con éxito: ni el acierto de caché de arriba ni un error más abajo
      // (que se propaga sin pasar por esta línea) gastan un comentario.
      _commentsGenerated++;
      _cache[key] = _CachedComment(comment, _changeNotifier.version);
      return comment;
    } finally {
      _isGenerating = false;
    }
  }

  String _cacheKey(MonthlyReport report) => '${report.year}-${report.month}';
}

class _CachedComment {
  _CachedComment(this.comment, this.transactionsVersion);

  final String comment;
  final int transactionsVersion;
}
