# NEXVORA AI

تطبيق محادثة عربي بواجهة داكنة، مع أدوات داخلية أولية للرد والبحث عبر الويب وفلترة بعض الكلمات ومساعدة البرمجة.

## بناء APK
يعمل GitHub Actions تلقائياً عند كل تحديث على فرع `main`. بعد نجاح البناء افتح تبويب **Actions** ثم اختر آخر تشغيل وحمّل artifact باسم **NEXVORA-AI-APK**.

## ملاحظات مهمة
- البحث يستخدم DuckDuckGo Instant Answer API؛ هذه خدمة إجابات فورية وليست محرك بحث شاملاً، وقد لا تعيد نتيجة لكل استفسار.
- فلترة المحتوى الحالية أساسية وتعتمد على كلمات مفتاحية، وليست نظام حماية شامل.
- الردود الحالية منطق محلي تجريبي وليست نموذج ذكاء اصطناعي توليدي. لربط نموذج حقيقي يلزم خادم وسيط آمن وحفظ مفاتيح API في الخادم، لا داخل APK.
- الأدوات الخمس مخفية عن واجهة المستخدم، لكن هذه النسخة MVP وليست بنية تنفيذ أدوات معزولة على خادم.


## Autonomous coding agent — Phase 1

The first agent foundation is implemented under `lib/core`:

- `models/project_memory.dart`: typed project memory, file plan, task status, and generated-file ledger.
- `services/project_memory_service.dart`: local-first JSON persistence and per-project workspace directories.
- `services/incremental_project_generator.dart`: sequential file generation with dependency checks, checkpoints, atomic writes, failure records, and resume support.

The generator uses an injected `FileContentGenerator` callback. It is intentionally model-provider agnostic; Phase 2 will connect it to the multi-provider API router and dynamic agent skills. See `docs/PHASE_1_ARCHITECTURE.md`.
