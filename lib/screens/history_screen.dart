import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../services/app_storage.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final sessions = state.recognitionSessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('История'),
        actions: [
          if (sessions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Очистить историю',
              onPressed: () => _confirmClear(context, state),
            ),
        ],
      ),
      body: sessions.isEmpty
          ? _EmptyHistory()
          : _SessionList(sessions: sessions),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text('Все сохранённые сессии и статистика будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.clearAll();
    }
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'История пуста',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Результаты распознавания\nпоявятся здесь',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  final List<RecognitionSession> sessions;

  const _SessionList({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _SessionCard(session: sessions[index], index: index),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final RecognitionSession session;
  final int index;

  const _SessionCard({required this.session, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.camera_alt_outlined,
                color: AppTheme.primary, size: 20),
          ),
          title: Text(
            _formatDate(session.timestamp),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${session.itemCount} ${_plural(session.itemCount)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          children: session.items.map((item) => _ItemRow(item: item)).toList(),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    if (diff.inDays == 1) return 'Вчера, ${_time(dt)}';
    if (diff.inDays < 7) return '${diff.inDays} дн назад, ${_time(dt)}';

    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${_time(dt)}';
  }

  String _time(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _plural(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'предмет';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'предмета';
    }
    return 'предметов';
  }
}

class _ItemRow extends StatelessWidget {
  final RecognizedItem item;

  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Text(
            item.category,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(item.confidence * 100).round()}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
