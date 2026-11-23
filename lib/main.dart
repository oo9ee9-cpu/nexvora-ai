import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

void main() => runApp(const NexvoraApp());

class NexvoraApp extends StatelessWidget {
  const NexvoraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'NEXVORA AI',
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF0B0D16),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF8B7CFF), secondary: Color(0xFF38D9C5),
        surface: Color(0xFF171A29),
      ),
    ),
    home: const ChatScreen(),
  );
}

class ChatMessage {
  final String text;
  final bool user;
  final bool web;
  const ChatMessage(this.text, {this.user = false, this.web = false});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final scroll = ScrollController();
  final messages = <ChatMessage>[
    const ChatMessage('مرحباً! أنا NEXVORA AI. اسألني عمّا تريد، ويمكنني البحث على الإنترنت ومساعدتك في البرمجة.')
  ];
  bool busy = false;
  bool webEnabled = true;

  static const blocked = ['إباحية', 'صور إباحية', 'porn', 'xxx', 'استغلال جنسي للأطفال'];

  bool isBlocked(String value) {
    final s = value.toLowerCase();
    return blocked.any((word) => s.contains(word));
  }

  Future<String> searchWeb(String query) async {
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query});
    final response = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml',
    }).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('تعذر الوصول إلى محرك البحث (${response.statusCode})');
    }
    final document = html_parser.parse(utf8.decode(response.bodyBytes));
    final links = document.querySelectorAll('a.result__a');
    final results = <String>[];
    for (final link in links) {
      final title = link.text.trim();
      var href = link.attributes['href'] ?? '';
      if (title.isEmpty || href.isEmpty) continue;
      final parsed = Uri.tryParse(href);
      if (parsed != null && parsed.queryParameters.containsKey('uddg')) {
        href = parsed.queryParameters['uddg'] ?? href;
      } else if (href.startsWith('//')) {
        href = 'https:' + href;
      }
      final snippet = link.parent?.parent?.querySelector('.result__snippet')?.text.trim() ?? '';
      if (href.startsWith('http')) {
        results.add('${results.length + 1}. $title\n$snippet\n$href');
      }
      if (results.length >= 6) break;
    }
    if (results.isEmpty) {
      return 'لم يعثر البحث على نتائج واضحة لهذا السؤال. جرّب صياغته بكلمات مختلفة.';
    }
    return 'هذه نتائج البحث على الإنترنت:\n\n${results.join('\n\n')}\n\nالإجابة مبنية على مقتطفات نتائج البحث؛ افتح الروابط للتحقق من التفاصيل الكاملة.';
  }

  Future<void> send() async {
    final text = controller.text.trim();
    if (text.isEmpty || busy) return;
    controller.clear();
    setState(() {
      messages.add(ChatMessage(text, user: true));
      busy = true;
    });
    _scrollDown();
    String answer;
    bool usedWeb = false;
    if (isBlocked(text)) {
      answer = 'لا أستطيع المساعدة في هذا النوع من المحتوى. يمكنني البحث عن معلومات آمنة وبديلة.';
    } else {
      try {
        answer = await searchWeb(text);
        usedWeb = answer.startsWith('هذه نتائج البحث');
      } catch (e) {
        answer = 'تعذر تنفيذ البحث الآن. تحقق من اتصال الإنترنت وحاول مرة أخرى.\n\n$e';
      }
    }
    if (!mounted) return;
    setState(() {
      messages.add(ChatMessage(answer, web: usedWeb));
      busy = false;
    });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF101321),
        title: Row(children: [
          Container(width: 38, height: 38,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(colors: [Color(0xFF8B7CFF), Color(0xFF35D8C4)])),
            child: const Icon(Icons.auto_awesome, color: Colors.white)),
          const SizedBox(width: 11),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NEXVORA AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            Text('مساعدك الذكي', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        ]),
        actions: [
          IconButton(tooltip: 'البحث عبر الإنترنت',
            onPressed: () => setState(() => webEnabled = !webEnabled),
            icon: Icon(webEnabled ? Icons.travel_explore : Icons.travel_explore_outlined,
              color: webEnabled ? const Color(0xFF38D9C5) : Colors.white38)),
          IconButton(onPressed: () => setState(() => messages
            ..clear()..add(const ChatMessage('بدأت محادثة جديدة. كيف أساعدك؟'))),
            icon: const Icon(Icons.add_comment_outlined)),
        ],
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 8), padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: const Color(0xFF171A29), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(.06))),
          child: Row(children: [
            const Icon(Icons.bolt, color: Color(0xFF38D9C5), size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(webEnabled ? 'الإجابة من نتائج البحث على الإنترنت' : 'الإجابة من نتائج البحث على الإنترنت',
              style: const TextStyle(fontSize: 12, color: Colors.white70))),
            Container(width: 7, height: 7, decoration: const BoxDecoration(
              color: Color(0xFF38D9C5), shape: BoxShape.circle)),
          ]),
        ),
        Expanded(child: ListView.builder(
          controller: scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          itemCount: messages.length + (busy ? 1 : 0),
          itemBuilder: (context, index) {
            if (busy && index == messages.length) {
              return const Align(alignment: Alignment.centerRight, child: Padding(
                padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))));
            }
            final m = messages[index];
            return Align(
              alignment: m.user ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
                margin: const EdgeInsets.only(bottom: 13),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                decoration: BoxDecoration(
                  color: m.user ? const Color(0xFF34304F) : const Color(0xFF191D2D),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(17), topRight: const Radius.circular(17),
                    bottomLeft: Radius.circular(m.user ? 5 : 17),
                    bottomRight: Radius.circular(m.user ? 17 : 5)),
                  border: Border.all(color: Colors.white.withOpacity(.055))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (m.web) const Padding(padding: EdgeInsets.only(bottom: 7),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.public, size: 13, color: Color(0xFF38D9C5)),
                      SizedBox(width: 5),
                      Text('بحث الويب', style: TextStyle(fontSize: 11, color: Color(0xFF38D9C5))),
                    ])),
                  SelectableText(m.text, style: const TextStyle(fontSize: 14, height: 1.65, color: Colors.white)),
                ]),
              ),
            );
          },
        )),
        Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 18),
          decoration: const BoxDecoration(color: Color(0xFF101321),
            border: Border(top: BorderSide(color: Color(0x1FFFFFFF)))),
          child: Row(children: [
            Expanded(child: Container(
              decoration: BoxDecoration(color: const Color(0xFF1B1E2D), borderRadius: BorderRadius.circular(25)),
              child: TextField(
                controller: controller, minLines: 1, maxLines: 5,
                textInputAction: TextInputAction.send, onSubmitted: (_) => send(),
                decoration: const InputDecoration(
                  hintText: 'اكتب سؤالك للبحث...', hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                  border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 13)),
              ),
            )),
            const SizedBox(width: 9),
            Material(color: const Color(0xFF8172F4), shape: const CircleBorder(),
              child: IconButton(onPressed: send, icon: const Icon(Icons.arrow_upward, color: Colors.white))),
          ]),
        ),
      ]),
    ));
  }
}
