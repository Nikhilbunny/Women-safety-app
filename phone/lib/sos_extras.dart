import 'alarm_service.dart';
import 'call_service.dart';
import 'db.dart';

/// Optional actions that run around an SOS, controlled by switches on the home screen.
class SosExtras {
  /// Right after the cancel window ends, before the SMS is sent.
  static Future<void> beforeSend() async {
    if (await AppDb.instance.getSetting('alarm_on_sos') == '1') {
      final sound = await AppDb.instance.getSetting('alarm_sound') ?? 'siren';
      await AlarmService.start(sound);
    }
  }

  /// After the SMS has been sent or queued.
  static Future<void> afterSend() async {
    if (await AppDb.instance.getSetting('call_on_sos') == '1') {
      final contacts = await AppDb.instance.contacts();
      await CallService.instance.startChain(contacts);
    }
  }
}
