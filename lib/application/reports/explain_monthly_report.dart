import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/reports/monthly_report.dart';
import '../../domain/reports/monthly_report_gateway.dart';
import '../../domain/transactions/llm_gateway_exception.dart';

/// Asks the AI for a comment on an already-computed [MonthlyReport],
/// with the same quota cap as `SendChatMessage`: at most
/// [maxCommentsPerSession] successful calls per session (one
/// instance), an in-memory cache per month (invalidated if the
/// transactions change), and no simultaneous calls.
///
/// Doesn't decide here what to do if the month has no transactions
/// ("No hay movimientos este mes"): the screen already knows that from
/// the `MonthlyReport` it already has, so it doesn't need to call this
/// use case to show it.
class ExplainMonthlyReport {
  ExplainMonthlyReport(this._gateway, [TransactionsChangeNotifier? changeNotifier])
    : _changeNotifier = changeNotifier ?? TransactionsChangeNotifier();

  /// Cap on successfully generated comments per session (one
  /// instance; see the provider that creates it). Same as in the
  /// chat, neither an answer served from the cache nor one that ends
  /// in error (network, quota, 503, timeout...) spends one of the 6,
  /// because neither one really costs quota.
  ///
  /// 6, not 3: same reason as
  /// `SendChatMessage.maxQuestionsPerSession` (daily quota of 500
  /// requests/day observed on 11/10/2026 with `gemini-3.5-flash-lite`).
  /// See docs/design.md.
  static const maxCommentsPerSession = 6;

  final MonthlyReportGateway _gateway;
  final TransactionsChangeNotifier _changeNotifier;
  final _cache = <String, _CachedComment>{};

  bool _isGenerating = false;
  int _commentsGenerated = 0;

  /// Comments left in this session before reaching
  /// [maxCommentsPerSession]. Never negative.
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

      // Only counted here, after a model call that has succeeded:
      // neither the cache hit above nor an error below (which
      // propagates without passing through this line) spend a comment.
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
