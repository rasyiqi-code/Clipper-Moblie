import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/insight_article.dart';
import '../../core/services/insight_service.dart';
import '../../core/theme/app_theme.dart';

class InsightScreen extends StatefulWidget {
  const InsightScreen({super.key});

  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  final InsightService _service = InsightService();

  late Future<List<InsightArticle>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchArticles();
  }

  Future<void> _reload() async {
    final next = _service.fetchArticles();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _openArticle(InsightArticle article) async {
    final uri = Uri.tryParse(article.link);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka: ${article.link}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(colors),
            Expanded(
              child: FutureBuilder<List<InsightArticle>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return _buildError(colors);
                  }
                  final articles = snapshot.data!;
                  if (articles.isEmpty) {
                    return _buildError(
                      colors,
                      message: 'Belum ada artikel dari feed.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _reload,
                    color: AppTheme.primaryGold,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                      itemCount: articles.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index == 0) return _buildFeedMeta(colors);
                        return _buildArticleCard(
                          articles[index - 1],
                          index,
                          articles.length,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.lightbulb_outline,
              color: Colors.black,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Insight',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 1),
                Text(
                  'Wawasan bisnis & teknologi',
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.workspace_premium,
            color: AppTheme.primaryGold,
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildFeedMeta(AppColors colors) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Konten diambil dari feed resmi Crediblemark.',
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.primaryGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.primaryGold.withValues(alpha: 0.4),
            ),
          ),
          child: const Text(
            '© Crediblemark',
            style: TextStyle(
              color: AppTheme.primaryGold,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArticleCard(InsightArticle article, int index, int total) {
    final colors = context.appColors;
    return Semantics(
      container: true,
      button: true,
      explicitChildNodes: true,
      label: 'article-$index',
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openArticle(article),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (article.categories.isNotEmpty) ...[
                  _buildCategories(article.categories),
                  const SizedBox(height: 6),
                ],
                Text(
                  article.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 14,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (article.summary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    article.summary,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 11,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(article.published),
                      style: TextStyle(color: colors.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Article $index/$total',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      label: 'link-$index',
                      child: Icon(
                        Icons.open_in_new,
                        size: 13,
                        color: AppTheme.primaryGold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategories(List<String> categories) {
    final shown = categories.take(3).toList();
    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: [
        for (final category in shown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              category,
              style: const TextStyle(
                color: AppTheme.primaryGold,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildError(AppColors colors, {String? message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36, color: Colors.grey),
            const SizedBox(height: 10),
            Text(
              message ??
                  'Gagal memuat Insight. Periksa koneksi internet lalu coba lagi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Muat Ulang'),
            ),
            const SizedBox(height: 10),
            const Text(
              '© Crediblemark (crediblemark.com)',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Belum ada tanggal';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
