import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

class SearchResult {
  final String title;
  final String snippet;
  final String url;
  const SearchResult(this.title, this.snippet, this.url);
}

class ApiProfile {
  final String name;
  final String endpoint;
  final String model;
  final String key;
  const ApiProfile({required this.name, required this.endpoint, required this.model, required this.key});
  Map<String, dynamic> toJson() => {'name': name, 'endpoint': endpoint, 'model': model, 'key': key};
  factory ApiProfile.fromJson(Map<String, dynamic> json) => ApiProfile(
    name: json['name'] ?? '', endpoint: json['endpoint'] ?? '',
    model: json['model'] ?? '', key: json['key'] ?? '',
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _secure = FlutterSecureStorage();
  final controller = TextEditingController();
  final scroll = ScrollController();
  final messages = <ChatMessage>[
    const ChatMessage('مرحباً! أنا NEXVORA AI. يمكنك البحث على الإنترنت أو ربط مزود ذكاء اصطناعي من قائمة تخصيص.')
  ];
  final profiles = <ApiProfile>[];
  bool busy = false;
  bool webEnabled = true;
  bool apiMode = false;
  int selectedApi = 0;

  static const blocked = ['إباحية', 'صور إباحية', 'porn', 'xxx', 'استغلال جنسي للأطفال'];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      final raw = await _secure.read(key: 'nexvora_api_profiles');
      if (raw == null) return;
      final decoded = jsonDecode(raw) as List;
      if (!mounted) return;
      setState(() {
        profiles
          ..clear()
          ..addAll(decoded.map((e) => ApiProfile.fromJson(Map<String, dynamic>.from(e))).take(50));
      });
    } catch (_) {}
  }

  Future<void> _saveProfiles() async {
    await _secure.write(
      key: 'nexvora_api_profiles',
      value: jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  bool isBlocked(String value) {
    final s = value.toLowerCase();
    return blocked.any((word) => s.contains(word));
  }

  Future<List<SearchResult>> _searchDuckDuckGo(String query) async {
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query});
    final response = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('DuckDuckGo: HTTP ${response.statusCode}');
    final doc = html_parser.parse(utf8.decode(response.bodyBytes));
    final output = <SearchResult>[];
    for (final item in doc.querySelectorAll('.result')) {
      final link = item.querySelector('a.result__a');
      final title = link?.text.trim() ?? '';
      var href = link?.attributes['href'] ?? '';
      final parsed = Uri.tryParse(href);
      if (parsed != null && parsed.queryParameters.containsKey('uddg')) {
        href = parsed.queryParameters['uddg'] ?? href;
      } else if (href.startsWith('//')) {
        href = 'https:$href';
      }
      final snippet = item.querySelector('.result__snippet')?.text.trim() ?? '';
      if (title.isNotEmpty && href.startsWith('http')) {
        output.add(SearchResult(title, snippet, Uri.decodeFull(href)));
      }
      if (output.length == 6) break;
    }
    return output;
  }

  Future<List<SearchResult>> _searchBing(String query) async {
    final uri = Uri.https('www.bing.com', '/search', {'q': query});
    final response = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Bing: HTTP ${response.statusCode}');
    final doc = html_parser.parse(utf8.decode(response.bodyBytes));
    final output = <SearchResult>[];
    for (final item in doc.querySelectorAll('li.b_algo')) {
      final link = item.querySelector('h2 a');
      final title = link?.text.trim() ?? '';
      final href = link?.attributes['href'] ?? '';
      final snippet = item.querySelector('.b_caption p')?.text.trim() ??
          item.querySelector('p')?.text.trim() ?? '';
      if (title.isNotEmpty && href.startsWith('http')) {
        output.add(SearchResult(title, snippet, href));
      }
      if (output.length == 6) break;
    }
    return output;
  }

  Future<String> searchWeb(String query) async {
    final errors = <String>[];
    for (final provider in <Future<List<SearchResult>> Function()>[
      () => _searchDuckDuckGo(query), () => _searchBing(query),
    ]) {
      try {
        final results = await provider();
        if (results.isNotEmpty) {
          return 'نتائج البحث المباشر على الإنترنت:\n\n${results.asMap().entries.map((entry) {
            final r = entry.value;
            return '${entry.key + 1}. ${r.title}\n${r.snippet}\n${r.url}';
          }).join('\n\n')}\n\nهذه مقتطفات من محرك البحث. افتح المصدر للتحقق من التفاصيل الكاملة.';
        }
        errors.add('لم يُرجع المحرك نتائج.');
      } catch (e) { errors.add(e.toString()); }
    }
    return 'تعذر جلب نتائج البحث من الهاتف. قد تمنع الشبكة الطلبات المباشرة.\n${errors.join(' | ')}';
  }

  Future<String> askApi(String prompt) async {
    if (profiles.isEmpty) throw Exception('أضف مفتاح API من القائمة الجانبية أولاً.');
    final profile = profiles[selectedApi.clamp(0, profiles.length - 1)];
    final uri = Uri.tryParse(profile.endpoint);
    if (uri == null || !uri.hasScheme || profile.key.trim().isEmpty || profile.model.trim().isEmpty) {
      throw Exception('تحقق من رابط API والمفتاح واسم النموذج في تخصيص.');
    }
    final response = await http.post(uri,
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${profile.key}'},
      body: jsonEncode({
        'model': profile.model,
        'messages': [
          {'role': 'system', 'content': 'أنت مساعد NEXVORA AI. أجب باللغة التي يستخدمها المستخدم وبوضوح.'},
          {'role': 'user', 'content': prompt},
        ],
      }),
    ).timeout(const Duration(seconds: 60));
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data is Map ? (data['error']?.toString() ?? data.toString()) : data.toString();
      throw Exception('API HTTP ${response.statusCode}: $detail');
    }
    final answer = data['choices']?[0]?['message']?['content'];
    if (answer is String && answer.trim().isNotEmpty) return answer.trim();
    if (answer is List) {
      return answer.map((part) => part is Map ? (part['text'] ?? '').toString() : '').join('\n').trim();
    }
    throw Exception('استجابة API غير متوافقة مع تنسيق OpenAI Chat Completions.');
  }

  Future<void> addApiDialog({int? editIndex}) async {
    final existing = editIndex == null ? null : profiles[editIndex];
    final name = TextEditingController(text: existing?.name ?? '');
    final endpoint = TextEditingController(text: existing?.endpoint ?? '');
    final model = TextEditingController(text: existing?.model ?? '');
    final key = TextEditingController(text: existing?.key ?? '');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) =>
      AlertDialog(
        backgroundColor: const Color(0xFF191D2D),
        title: Text(editIndex == null ? 'إضافة اتصال API' : 'تعديل اتصال API'),
        content: SizedBox(width: 420, child: Form(key: formKey, child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم المزود (مثلاً Gemini)'),
              validator: (v) => v == null || v.trim().isEmpty ? 'أدخل الاسم' : null),
            TextFormField(controller: endpoint, decoration: const InputDecoration(labelText: 'رابط Chat Completions الكامل'),
              keyboardType: TextInputType.url,
              validator: (v) => Uri.tryParse(v ?? '')?.hasScheme == true ? null : 'أدخل رابطاً صحيحاً يبدأ بـ https://'),
            TextFormField(controller: model, decoration: const InputDecoration(labelText: 'اسم النموذج'),
              validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم النموذج' : null),
            TextFormField(controller: key, obscureText: true,
              decoration: const InputDecoration(labelText: 'مفتاح API')),
            const SizedBox(height: 8),
            const Text('يدعم هذا النموذج واجهات OpenAI Chat Completions المتوافقة. بعض مزودي API يحتاجون تنسيقاً خاصاً ولن يعملوا بهذا الاتصال العام.',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
            TextButton.icon(
              onPressed: () {
                name.text = 'Google Gemini';
                endpoint.text = 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
                model.text = 'gemini-2.5-flash';
              },
              icon: const Icon(Icons.auto_awesome), label: const Text('إعداد Gemini')),
          ]),
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
          }, child: const Text('حفظ')),
        ],
      ),
    );
    if (saved == true) {
      final profile = ApiProfile(name: name.text.trim(), endpoint: endpoint.text.trim(),
        model: model.text.trim(), key: key.text.trim());
      setState(() {
        if (editIndex == null) {
          if (profiles.length < 50) profiles.add(profile);
        } else {
          profiles[editIndex] = profile;
        }
        selectedApi = (editIndex ?? profiles.length - 1).clamp(0, profiles.isEmpty ? 0 : profiles.length - 1);
      });
      await _saveProfiles();
    }
    name.dispose(); endpoint.dispose(); model.dispose(); key.dispose();
  }

  Future<void> openCustomization() async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      backgroundColor: const Color(0xFF171A29),
      builder: (sheetContext) => StatefulBuilder(builder: (context, sheetSet) =>
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(
              color: Colors.white30, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 18),
            const Text('تخصيص NEXVORA AI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إيقاف بحث التطبيق'),
              subtitle: const Text('إيقاف البحث في الويب واستخدام API بدلاً منه'),
              value: !webEnabled,
              onChanged: (v) {
                setState(() { webEnabled = !v; if (v) apiMode = true; });
                sheetSet(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('استخدم API'),
              subtitle: const Text('إرسال أسئلتك إلى مزود الذكاء الاصطناعي المحدد'),
              value: apiMode,
              onChanged: (v) {
                setState(() => apiMode = v);
                sheetSet(() {});
              },
            ),
            if (profiles.isNotEmpty) DropdownButtonFormField<int>(
              value: selectedApi.clamp(0, profiles.length - 1),
              decoration: const InputDecoration(labelText: 'المزود النشط'),
              items: profiles.asMap().entries.map((e) =>
                DropdownMenuItem(value: e.key, child: Text('${e.value.name} — ${e.value.model}'))).toList(),
              onChanged: (v) {
                if (v != null) setState(() => selectedApi = v);
                sheetSet(() {});
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('اتصالات API: ${profiles.length}/50')),
              FilledButton.icon(
                onPressed: profiles.length >= 50 ? null : () async {
                  Navigator.pop(sheetContext);
                  await addApiDialog();
                },
                icon: const Icon(Icons.add), label: const Text('إضافة مفتاح')),
            ]),
            if (profiles.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 10), child: Text('لم تضف أي مزود بعد. أضف مفتاحك لتفعيل المحادثة بالذكاء الاصطناعي.',
                style: TextStyle(color: Colors.white60))),
            if (profiles.isNotEmpty)
              Flexible(child: ListView.builder(shrinkWrap: true, itemCount: profiles.length,
                itemBuilder: (context, i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key, color: Color(0xFF38D9C5)),
                  title: Text(profiles[i].name),
                  subtitle: Text('${profiles[i].model} • المفتاح محفوظ محلياً بشكل مشفر'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') {
                        Navigator.pop(sheetContext);
                        await addApiDialog(editIndex: i);
                      } else if (action == 'delete') {
                        setState(() { profiles.removeAt(i); selectedApi = 0; });
                        await _saveProfiles();
                        sheetSet(() {});
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ))),
          ]),
        )),
      ),
    );
  }

  void openDrawerPage(String title) {
    Navigator.pop(context);
    if (title == 'تخصيص') { openCustomization(); return; }
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF191D2D), title: Text(title),
      content: Text(title == 'حول التطبيق'
        ? 'NEXVORA AI\nمساعدك الذكي. المطور: حيدر.'
        : 'قسم $title — ستتوفر إعداداته في تحديث لاحق.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
    ));
  }

  Future<void> send() async {
    final text = controller.text.trim();
    if (text.isEmpty || busy) return;
    controller.clear();
    setState(() { messages.add(ChatMessage(text, user: true)); busy = true; });
    _scrollDown();
    String answer;
    bool usedWeb = false;
    if (isBlocked(text)) {
      answer = 'لا أستطيع المساعدة في هذا النوع من المحتوى. يمكنني البحث عن معلومات آمنة وبديلة.';
    } else {
      try {
        if (apiMode) {
          answer = await askApi(text);
        } else if (webEnabled) {
          answer = await searchWeb(text);
          usedWeb = answer.startsWith('نتائج البحث المباشر');
        } else {
          answer = 'البحث متوقف. افتح تخصيص وفعّل استخدام API أو أعد تشغيل البحث.';
        }
      } catch (e) {
        answer = 'تعذر تنفيذ الطلب:\n$e';
      }
    }
    if (!mounted) return;
    setState(() { messages.add(ChatMessage(answer, web: usedWeb)); busy = false; });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    controller.dispose(); scroll.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      drawer: Drawer(
        backgroundColor: const Color(0xFF141827),
        child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.auto_awesome, size: 42, color: Color(0xFF38D9C5)),
            SizedBox(height: 10), Text('NEXVORA AI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text('القائمة الرئيسية', style: TextStyle(color: Colors.white54)),
          ])),
          const Divider(color: Colors.white12),
          for (final item in [
            ['تخصيص', Icons.tune], ['الخصوصية', Icons.shield_outlined],
            ['الإعدادات', Icons.settings_outlined], ['المظهر', Icons.palette_outlined],
            ['شعارات', Icons.campaign_outlined], ['الإصدار', Icons.info_outline],
            ['التحديثات', Icons.system_update_alt], ['حول التطبيق', Icons.help_outline],
          ])
            ListTile(leading: Icon(item[1] as IconData, color: const Color(0xFF38D9C5)),
              title: Text(item[0] as String), onTap: () => openDrawerPage(item[0] as String)),
        ])),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101321),
        leading: Builder(builder: (context) => IconButton(
          icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(context).openDrawer())),
        title: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [Color(0xFF8B7CFF), Color(0xFF35D8C4)])),
            child: const Icon(Icons.auto_awesome, color: Colors.white)),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NEXVORA AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            Text('مساعدك الذكي', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        ]),
        actions: [
          IconButton(tooltip: 'تخصيص', onPressed: openCustomization,
            icon: const Icon(Icons.tune, color: Color(0xFF38D9C5))),
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
            Expanded(child: Text(apiMode ? 'المحادثة عبر API' : (webEnabled ? 'بحث مباشر من الهاتف دون خادم خاص' : 'البحث متوقف'),
              style: const TextStyle(fontSize: 12, color: Colors.white70))),
            Container(width: 7, height: 7, decoration: BoxDecoration(
              color: apiMode || webEnabled ? const Color(0xFF38D9C5) : Colors.orange,
              shape: BoxShape.circle)),
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
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .90),
                margin: const EdgeInsets.only(bottom: 13),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                decoration: BoxDecoration(
                  color: m.user ? const Color(0xFF34304F) : const Color(0xFF191D2D),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: Colors.white.withOpacity(.055))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (m.web) const Padding(padding: EdgeInsets.only(bottom: 7),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.public, size: 13, color: Color(0xFF38D9C5)),
                      SizedBox(width: 5), Text('بحث الويب', style: TextStyle(fontSize: 11, color: Color(0xFF38D9C5))),
                    ])),
                  SelectableText(m.text, style: const TextStyle(fontSize: 14, height: 1.65, color: Colors.white)),
                ]),
              ),
            );
          },
        )),
        SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
          decoration: const BoxDecoration(color: Color(0xFF101321),
            border: Border(top: BorderSide(color: Color(0x1FFFFFFF)))),
          child: Row(children: [
            Expanded(child: Container(
              decoration: BoxDecoration(color: const Color(0xFF1B1E2D), borderRadius: BorderRadius.circular(25)),
              child: TextField(
                controller: controller, minLines: 1, maxLines: 5,
                textInputAction: TextInputAction.send, onSubmitted: (_) => send(),
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالتك...', hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                  border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 13)),
              ),
            )),
            const SizedBox(width: 9),
            Material(color: const Color(0xFF8172F4), shape: const CircleBorder(),
              child: IconButton(onPressed: send, icon: const Icon(Icons.arrow_upward, color: Colors.white))),
          ]),
        )),
      ]),
    ));
  }
}
