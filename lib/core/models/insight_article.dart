/// A single blog post from the Crediblemark RSS feed.
class InsightArticle {
  final String title;
  final String link;
  final DateTime? published;
  final String summary;
  final List<String> categories;
  final String creator;

  const InsightArticle({
    required this.title,
    required this.link,
    required this.published,
    required this.summary,
    required this.categories,
    required this.creator,
  });

  factory InsightArticle.empty() => const InsightArticle(
    title: '',
    link: '',
    published: null,
    summary: '',
    categories: [],
    creator: '',
  );
}
