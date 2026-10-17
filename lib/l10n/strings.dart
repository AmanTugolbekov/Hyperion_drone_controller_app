import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';

/// Lightweight 3-language table. No codegen step, so adding a key is one line
/// per language and nothing else.
enum AppLang { ru, en, ky }

extension AppLangX on AppLang {
  String get code => switch (this) {
        AppLang.ru => 'ru',
        AppLang.en => 'en',
        AppLang.ky => 'ky',
      };

  String get label => switch (this) {
        AppLang.ru => 'Русский',
        AppLang.en => 'English',
        AppLang.ky => 'Кыргызча',
      };

  Locale get locale => Locale(code);

  static AppLang fromCode(String? c) =>
      AppLang.values.firstWhere((l) => l.code == c, orElse: () => AppLang.ru);
}

class S {
  final AppLang lang;
  const S(this.lang);

  /// The language comes from settings rather than from [Localizations]:
  /// Kyrgyz has no Material translations upstream, so the Material chrome is
  /// resolved to Russian while the app's own strings stay Kyrgyz.
  ///
  /// This deliberately does not subscribe to the provider, so that it is also
  /// legal from event handlers. Nothing is lost: `MaterialApp` sits inside a
  /// `Consumer<SettingsService>`, so changing the language rebuilds the whole
  /// tree anyway.
  static S of(BuildContext context) =>
      S(Provider.of<SettingsService>(context, listen: false).lang);

  String t(String key) {
    final row = _table[key];
    if (row == null) return key;
    // Fall back to Russian when a row is missing a translation.
    return lang.index < row.length ? row[lang.index] : row.first;
  }

  // [ru, en, ky]
  static const Map<String, List<String>> _table = {
    'app_title': ['Ala-Too Drone', 'Ala-Too Drone', 'Ala-Too Drone'],
    'app_subtitle': [
      'Международный университет Ала-Тоо',
      'Ala-Too International University',
      'Ала-Тоо эл аралык университети',
    ],

    // Connect screen
    'connect_title': ['Подключение', 'Connection', 'Туташуу'],
    'connect_hint': [
      'Подключите телефон к Wi-Fi сети дрона, затем нажмите «Подключиться».',
      'Connect your phone to the drone Wi-Fi network, then tap Connect.',
      'Телефонуңузду дрондун Wi-Fi тармагына туташтырып, «Туташуу» баскычын басыңыз.',
    ],
    'connect_btn': ['Подключиться', 'Connect', 'Туташуу'],
    'disconnect_btn': ['Отключиться', 'Disconnect', 'Ажыратуу'],
    'open_wifi': ['Открыть настройки Wi-Fi', 'Open Wi-Fi settings', 'Wi-Fi жөндөөлөрү'],
    'current_network': ['Текущая сеть', 'Current network', 'Учурдагы тармак'],
    'unknown_network': ['Не определена', 'Unknown', 'Белгисиз'],
    'searching': ['Поиск дрона…', 'Searching for drone…', 'Дрон изделүүдө…'],
    'connected': ['Подключено', 'Connected', 'Туташты'],
    'disconnected': ['Нет связи', 'No link', 'Байланыш жок'],
    'connecting': ['Соединение…', 'Connecting…', 'Туташууда…'],
    'conn_failed': [
      'Не удалось найти дрон. Проверьте Wi-Fi или задайте адрес вручную в Диагностике.',
      'Drone not found. Check Wi-Fi or set the address manually in Diagnostics.',
      'Дрон табылган жок. Wi-Fi текшериңиз же Диагностикада даректи кол менен жазыңыз.',
    ],

    // Flight
    'fly_title': ['Полёт', 'Flight', 'Учуу'],
    'takeoff': ['Взлёт', 'Take off', 'Учуу'],
    'land': ['Посадка', 'Land', 'Конуу'],
    'stop': ['СТОП', 'STOP', 'ТОКТО'],
    'emergency': ['Аварийная остановка', 'Emergency stop', 'Авариялык токтотуу'],
    'headless': ['Headless', 'Headless', 'Headless'],
    'speed': ['Скорость', 'Speed', 'Ылдамдык'],
    'altitude_hold': ['Удержание высоты', 'Altitude hold', 'Бийиктикти кармоо'],
    'gyro_mode': ['Управление наклоном', 'Tilt control', 'Эңкейтип башкаруу'],
    'calibrate': ['Калибровка гироскопа', 'Gyro calibration', 'Гироскопту тууралоо'],
    'calibrated': ['Гироскоп откалиброван', 'Gyro calibrated', 'Гироскоп тууралды'],
    'trim': ['Триммер', 'Trim', 'Триммер'],
    'flip': ['Флип 360°', '360° flip', 'Флип 360°'],
    'photo': ['Фото', 'Photo', 'Сүрөт'],
    'video': ['Видео', 'Video', 'Видео'],
    'rec': ['Запись', 'Recording', 'Жазуу'],
    'gallery': ['Галерея', 'Gallery', 'Галерея'],
    'battery': ['Батарея', 'Battery', 'Батарея'],
    'signal': ['Сигнал', 'Signal', 'Сигнал'],
    'no_video': ['Нет видеосигнала', 'No video feed', 'Видео жок'],
    'rotate_phone': [
      'Поверните телефон горизонтально',
      'Turn your phone sideways',
      'Телефонду туурасынан буруңуз',
    ],
    'wifi_not_bound': [
      'Трафик может идти через мобильный интернет — отключите мобильные данные',
      'Traffic may go over mobile data — turn mobile data off',
      'Трафик мобилдик интернет аркылуу кетиши мүмкүн — мобилдик дайындарды өчүрүңүз',
    ],
    'photo_saved': ['Фото сохранено', 'Photo saved', 'Сүрөт сакталды'],
    'video_saved': ['Видео сохранено', 'Video saved', 'Видео сакталды'],

    // Settings
    'settings': ['Настройки', 'Settings', 'Жөндөөлөр'],
    'language': ['Язык', 'Language', 'Тил'],
    'protocol': ['Протокол дрона', 'Drone protocol', 'Дрон протоколу'],
    'protocol_auto': ['Автоопределение', 'Auto-detect', 'Автоматтык'],
    'controls': ['Управление', 'Controls', 'Башкаруу'],
    'left_stick_throttle': [
      'Газ на левом стике',
      'Throttle on left stick',
      'Газ сол стикте',
    ],
    'haptics': ['Вибрация', 'Haptic feedback', 'Дирилдөө'],
    'keep_screen_on': ['Не гасить экран', 'Keep screen on', 'Экран өчпөсүн'],
    'diagnostics': ['Диагностика', 'Diagnostics', 'Диагностика'],
    'host': ['IP дрона', 'Drone IP', 'Дрондун IP'],
    'cmd_port': ['Порт команд', 'Command port', 'Команда порту'],
    'video_port': ['Порт видео', 'Video port', 'Видео порту'],
    'test_connection': ['Проверить', 'Test', 'Текшерүү'],
    'log': ['Журнал', 'Log', 'Журнал'],
    'scan_drone': ['Сканировать дрон', 'Scan drone', 'Дронду скандоо'],
    'scanning': ['Сканирование…', 'Scanning…', 'Скандалууда…'],
    'copy_log': ['Скопировать журнал', 'Copy log', 'Журналды көчүрүү'],
    'log_copied': ['Журнал скопирован', 'Log copied', 'Журнал көчүрүлдү'],
    'save': ['Сохранить', 'Save', 'Сактоо'],
    'about': ['О приложении', 'About', 'Тиркеме жөнүндө'],
    'about_text': [
      'Учебный проект Международного университета Ала-Тоо.',
      'An educational project of Ala-Too International University.',
      'Ала-Тоо эл аралык университетинин окуу долбоору.',
    ],

    // Common
    'cancel': ['Отмена', 'Cancel', 'Жокко чыгаруу'],
    'ok': ['Готово', 'Done', 'Даяр'],
    'empty_gallery': ['Пока пусто', 'Nothing here yet', 'Азырынча бош'],
    'permission_needed': [
      'Нужны разрешения на Wi-Fi и хранилище',
      'Wi-Fi and storage permissions are required',
      'Wi-Fi жана сактагычка уруксат керек',
    ],
  };
}
