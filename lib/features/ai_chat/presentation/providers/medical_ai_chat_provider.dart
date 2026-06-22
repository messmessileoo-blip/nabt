import 'package:digl/features/ai_chat/data/services/medical_ai_error_handler.dart';
import 'package:digl/features/ai_chat/presentation/pages/medical_ai_chat_screen.dart';
import 'package:flutter/material.dart';
import '../../data/models/ai_chat_message.dart';
import '../../data/models/medical_intake.dart';
import '../../data/repositories/medical_ai_repository.dart';

class MedicalAiChatProvider extends ChangeNotifier {
  final MedicalAiRepository repository;
  MedicalAiChatProvider(this.repository);

  final List<AiChatMessage> messages = [];
  bool isLoading = false;
  String? error;

  Future<void> loadLocalHistory() async {
    messages
      ..clear()
      ..addAll(await repository.loadLocalMessages());
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> clearMessages() async {
    messages.clear();
    error = null;
    await repository.clearMessages();
    notifyListeners();
  }

  Future<String> buildInitialRecommendation(MedicalIntake intake) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final doctors = await repository.recommendDoctors(intake);
      final doctorText = doctors.isEmpty
          ? 'لم يتم العثور على طبيب مطابق حالياً داخل التطبيق.'
          : 'أفضل طبيب مقترح: ${doctors.first.fullName} - ${doctors.first.specialtyName} (تطابق ${doctors.first.matchPercentage}%).';
      final recommendation = 'التخصص المقترح: ${doctors.isEmpty ? 'طب عام' : doctors.first.specialtyName}.\n$doctorText\nالتوصية: احجز موعداً إذا استمرت الأعراض أو كانت الشدة عالية.';
      await _addBot(recommendation);
      return recommendation;
    } catch (e) {
      error = MedicalAiErrorHandler.friendlyMessage(e);
      return error!;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> send(MedicalIntake intake, String content) async {
    if (content.trim().isEmpty) return;
    await _addUser(content.trim());
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final reply = await repository.sendMessage(intake, messages, content.trim());
      await _addBot(reply);
    } catch (e) {
      error = MedicalAiErrorHandler.friendlyMessage(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendAttachment(MedicalIntake intake, String path, String type, {String? description}) async {
    final cleanDescription = description?.trim() ?? '';
    final label = type == 'image'
        ? 'تم رفع صورة للتحليل.${cleanDescription.isEmpty ? '' : '\nوصف المستخدم للصورة: $cleanDescription'}\nافحص الصورة نفسها: إن كانت فحصاً أو تحليلاً فاستخرج النصوص والقيم المقروءة واشرحها، وإن كانت دواءً فحدد الاسم الظاهر أو الأقرب والاستخدام والتحذيرات العامة.'
        : 'تم رفع ملف للمراجعة${cleanDescription.isEmpty ? '' : ': $cleanDescription'}';
    await _add(AiChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), content: label, isUser: true, createdAt: DateTime.now(), attachmentPath: path, attachmentType: type));
    isLoading = true; error = null; notifyListeners();
    try {
      final reply = await repository.sendMessage(
        intake,
        messages,
        label,
        attachmentPath: path,
        attachmentType: type,
      );
      await _addBot(reply.isEmpty ? 'تم استلام المرفق. صف لي ما تريد تحليله بالتحديد.' : reply);
    } catch (e) { error = MedicalAiErrorHandler.friendlyMessage(e); }
    finally { isLoading = false; notifyListeners(); }
  }


  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MedicalAiChatScreen(),
        settings: const RouteSettings(name: '/medical_ai_chat'),
      ),
    );
  }

  static Widget floatingButton(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'global_ai_chat_fab',
      elevation: 0,
      highlightElevation: 0,
      onPressed: () => open(context),
      icon: const Icon(Icons.smart_toy_rounded),
      label: const Text('مساعدك الشخصي'),
    );
  }

  Future<void> deleteMessage(AiChatMessage message) async {
    messages.removeWhere((item) => item.id == message.id);
    notifyListeners();
    await repository.deleteMessage(message);
  }

  Future<void> resend(MedicalIntake intake, AiChatMessage message) async {
    if (!message.isUser || message.content.trim().isEmpty || isLoading) return;
    await send(intake, message.content);
  }

  Future<void> _addUser(String content) async => _add(AiChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), content: content, isUser: true, createdAt: DateTime.now()));
  Future<void> _addBot(String content) async => _add(AiChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), content: content, isUser: false, createdAt: DateTime.now()));
  Future<void> _add(AiChatMessage msg) async {
    messages.add(msg);
    notifyListeners();
    await repository.saveMessage(msg);
  }
}
