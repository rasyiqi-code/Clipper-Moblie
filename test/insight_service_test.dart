import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:clipper_mobile/core/services/insight_service.dart';

const _sampleFeed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
  <title>Blog Crediblemark</title>
  <link>https://blog.crediblemark.com</link>
  <description>Build to Grow. Design to Last</description>
  <item>
    <title>Judul Artikel Satu</title>
    <link>https://blog.crediblemark.com/artikel-satu/</link>
    <pubDate>Thu, 16 Jul 2026 11:11:23 +0000</pubDate>
    <category><![CDATA[Bisnis]]></category>
    <category><![CDATA[Efisiensi]]></category>
    <description><![CDATA[<p>Ringkasan <b>singkat</b> artikel [&#8230;]</p>]]></description>
  </item>
  <item>
    <title>Judul Artikel Dua</title>
    <link>https://blog.crediblemark.com/artikel-dua/</link>
    <description>Tanpa tanggal</description>
  </item>
</channel>
</rss>''';

void main() {
  group('InsightService', () {
    test('parses title, link, date, categories and cleans HTML summary', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), InsightService.feedUrl);
        return http.Response(_sampleFeed, 200,
            headers: {'content-type': 'text/xml'});
      });

      final service = InsightService(client: client);
      final articles = await service.fetchArticles();

      expect(articles, hasLength(2));

      final first = articles.first;
      expect(first.title, 'Judul Artikel Satu');
      expect(first.link, 'https://blog.crediblemark.com/artikel-satu/');
      expect(first.published, DateTime.utc(2026, 7, 16, 11, 11, 23));
      expect(first.categories, ['Bisnis', 'Efisiensi']);
      expect(first.summary, contains('Ringkasan singkat artikel […]'));

      final second = articles[1];
      expect(second.published, isNull);
      expect(second.summary, 'Tanpa tanggal');
    });

    test('throws when the feed returns a non-200 status', () async {
      final client = MockClient((_) async => http.Response('oops', 500));
      final service = InsightService(client: client);
      expect(service.fetchArticles(), throwsException);
    });
  });
}
