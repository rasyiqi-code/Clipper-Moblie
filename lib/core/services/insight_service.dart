import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/insight_article.dart';

/// Fetches and parses the Crediblemark blog RSS feed.
class InsightService {
  static const String feedUrl = 'https://blog.crediblemark.com/feed/';

  final http.Client _client;

  InsightService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<InsightArticle>> fetchArticles() async {
    final response = await _client
        .get(
          Uri.parse(feedUrl),
          headers: const {'User-Agent': 'Mozilla/5.0 (Android) clipper_mobile'},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw HttpException(
        'Feed gagal dimuat (HTTP ${response.statusCode})',
        uri: Uri.parse(feedUrl),
      );
    }

    final document = XmlDocument.parse(response.body);
    final items = document.findAllElements('item').toList();

    final articles = <InsightArticle>[];
    for (final item in items) {
      final article = _parseItem(item);
      if (article.title.isNotEmpty && article.link.isNotEmpty) {
        articles.add(article);
      }
    }
    return articles;
  }

  InsightArticle _parseItem(XmlElement item) {
    String textOf(String name) {
      final node = item.getElement(name);
      if (node == null) return '';
      return node.innerText.trim();
    }

    final pubDateRaw = textOf('pubDate');
    final categories = item
        .findElements('category')
        .map((c) => c.innerText.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    return InsightArticle(
      title: textOf('title'),
      link: textOf('link'),
      published: _parseDate(pubDateRaw),
      summary: _htmlToText(textOf('description')),
      categories: categories,
      creator: textOf('creator'),
    );
  }

  DateTime? _parseDate(String raw) {
    // RFC 822/1123: "Thu, 16 Jul 2026 11:11:23 +0000".
    // Dart's HttpDate only accepts the literal "GMT" zone, so parse manually.
    final match = RegExp(
      r'^\s*(?:[A-Za-z]{3},)?\s*(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})'
      r'\s+(\d{2}):(\d{2}):(\d{2})\s*([+-]\d{4})?\s*$',
    ).firstMatch(raw);
    if (match == null) return null;

    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) return null;

    final day = int.parse(match.group(1)!);
    final year = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);

    final date = DateTime.utc(year, month, day, hour, minute, second);
    final zone = match.group(7);
    if (zone != null && zone.isNotEmpty) {
      final sign = zone.startsWith('-') ? -1 : 1;
      final hours = int.parse(zone.substring(1, 3));
      final minutes = int.parse(zone.substring(3, 5));
      return date.subtract(Duration(minutes: sign * (hours * 60 + minutes)));
    }
    return date;
  }

  /// Strips HTML tags and decodes common entities from the feed summary.
  String _htmlToText(String html) {
    var text = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = text
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final code = int.tryParse(m.group(1)!, radix: 16);
          return code == null ? '' : String.fromCharCode(code);
        })
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          return code == null ? '' : String.fromCharCode(code);
        });

    const entities = <String, String>{
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&apos;': "'",
      '&#8230;': '…',
      '&hellip;': '…',
    };
    for (final entry in entities.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }
}
