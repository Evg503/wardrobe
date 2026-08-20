# Wardrobe — История разработки

## Версии приложения

| Версия | Build | Коммит | Что изменилось |
|--------|-------|--------|----------------|
| 1.0.0 | 1 | `06da1b0` | Первый релиз: UI, камера, ML Kit, ARKit, персистентность |
| 1.1.0 | — | `2ce243a` | ARCore Android, экспорт PNG/PDF, EfficientDet-Lite0, онбординг |
| 1.2.0 | 2 | `1642c9c` | Отображение версии в UI, исправления багов ARCore |
| 1.3.0 | 3 | — | Фикс чёрного экрана ARCore (OES-текстура), фикс NPE в ML Kit (yuv420) |

> Правило: версия поднимается с каждым билдом. Формат `pubspec.yaml`: `major.minor.patch+buildNumber`.

---

## Стек технологий

- **Flutter 3.47.0** / Dart — кроссплатформенный фреймворк (iOS + Android)
- **Material 3** — дизайн-система
- **camera ^0.11.0** — живой видеопоток с камеры
- **google_mlkit_object_detection ^0.14.0** — распознавание объектов на устройстве
- **arkit_plugin ^1.5.0** — AR-сканирование планировки (iOS)
- **shared_preferences ^2.3.0** — локальное хранилище данных
- **vector_math ^2.1.4** — математика для AR
- **pdf ^3.11.0** — векторная генерация PDF
- **path_provider ^2.1.0** — доступ к временной директории
- **share_plus ^10.0.0** — системный шит для отправки файлов

---

## Этапы разработки

### 1. Исходный UI-прототип (`447b66c`)

Создан Flutter-проект с тремя вкладками:

- **Главная** — дашборд со счётчиками и карточками-переходами
- **План квартиры** — три состояния (пусто / сканирование / результат), анимированный индикатор, план нарисован через `CustomPainter`
- **Распознавание предметов** — мок-видоискатель с сеткой, 4 захардкоженных объекта добавляются с задержкой

Вся бизнес-логика была заглушкой. Архитектура: `StatefulWidget` + `setState`, без сторонних state management решений.

---

### 2. Интеграция камеры (`0298aaa`)

Подключён пакет `camera ^0.11.0`.

**Новые файлы:**
- `lib/services/camera_service.dart` — `ChangeNotifier`-сервис: инициализация камер, переключение передняя/задняя, управление вспышкой (выкл/авто/вкл), захват фото
- `lib/widgets/camera_preview_widget.dart` — переиспользуемый виджет превью с кнопками управления и поддержкой внешних оверлеев

**Изменения:**
- `object_recognition_screen.dart` — мок-сетка заменена на реальный `CameraPreviewWidget`
- `floor_plan_screen.dart` — мок-сетка в режиме сканирования заменена на `CameraPreviewWidget`
- `AndroidManifest.xml` — разрешения `CAMERA`, `uses-feature`
- `build.gradle.kts` — `minSdk = 21` (требование пакета camera)
- `Info.plist` — `NSCameraUsageDescription` уже была

---

### 3. ML Kit: распознавание объектов (`8b4220d`)

Подключён `google_mlkit_object_detection ^0.14.0`.

**Новые файлы:**
- `lib/services/object_detection_service.dart` — детектор ML Kit: обработка кадров из `imageStream`, конвертация `CameraImage` → `InputImage` с корректной ориентацией (коррекция для фронтальной камеры), нормализация bounding box в 0..1, фильтрация по confidence < 40%, маппинг английских лейблов в русские названия и категории

**Изменения:**
- `object_recognition_screen.dart` — полностью переписан: реальный `imageStream`, кнопка Стоп в AppBar, нормализованные bounding-боксы через `LayoutBuilder`
- `camera_preview_widget.dart` — добавлен параметр `cameraService` для передачи внешнего экземпляра
- `build.gradle.kts` — `compileSdk = 34`, `aaptOptions` для `.tflite` файлов

---

### 4. Сборки (`d060692`, `51b8378`, `06da1b0`)

**Android APK:**
- Поднят `compileSdk` и `targetSdk` до 36 (требование `camera_android_camerax`)
- Результат: `build/app/outputs/flutter-apk/app-release.apk` (78 МБ)

**iOS .app:**
- Установлен CocoaPods 1.17.0
- Поднят `IPHONEOS_DEPLOYMENT_TARGET` до 16.0 (требование `google_mlkit_commons >= 15.5`)
- Установлен `platform :ios, '16.0'` в Podfile
- Сборка: `--no-codesign` (для установки на устройство нужна подпись через Xcode)
- Результат: `build/ios/Release-iphoneos/Runner.app` (36 МБ)

**Ветка releases:**
- Создана orphan-ветка `releases`
- Опубликованы: `wardrobe-1.0.0.apk` (78 МБ), `wardrobe-1.0.0-ios.zip` (11 МБ)

---

### 5. Персистентность данных (`4aef1cd`)

Подключён `shared_preferences ^2.3.0`.

**Новые файлы:**
- `lib/services/app_storage.dart` — типизированный слой над `shared_preferences`: счётчики комнат и предметов, список сессий распознавания в JSON
- `lib/services/app_state.dart` — `ChangeNotifier` + `AppStateScope` (InheritedNotifier), доступен через `AppStateScope.of(context)` из любого экрана
- `lib/screens/history_screen.dart` — список сессий с `ExpansionTile`, относительные временные метки («только что», «5 мин назад» и т.д.), кнопка очистки с подтверждением

**Изменения:**
- `main.dart` — `async` инициализация `AppState` до `runApp`
- `home_screen.dart` — счётчики читают реальные данные из `AppState`; добавлена вкладка «История» в `NavigationBar`
- `object_recognition_screen.dart` — при остановке потока сессия автоматически сохраняется

---

### 6. AR-сканирование планировки (`3761e6b`)

Подключён `arkit_plugin ^1.5.0` (iOS only). Для Android — заглушка с пояснением.

**Новые файлы:**
- `lib/services/ar_scan_service.dart` — модели `DetectedPlane`, `ScanResult`; сервис управляет списком обнаруженных плоскостей

**Изменения:**
- `floor_plan_screen.dart` — полностью переписан:
  - **iOS**: реальный `ARKitSceneView` с детектированием горизонтальных и вертикальных плоскостей, полупрозрачные цветные оверлеи на поверхностях, бейдж со счётчиком, угловые маркеры
  - **Android**: анимированная заглушка с пояснением о статусе ARCore
  - Тип плоскости (пол/стена) определяется по Y-нормали из матрицы трансформации `ARKitPlaneAnchor`
  - Кнопка «Завершить» активна только при наличии хотя бы одной плоскости
  - Экран результатов отображает реальные размеры из ARKit и площадь пола
- `app_storage.dart` + `app_state.dart` — добавлено хранение `ScanSession` (количество плоскостей, площадь пола, время)
- `Info.plist` — `NSMotionUsageDescription` для гироскопа ARKit
- `AndroidManifest.xml` — `com.google.ar.core optional` meta-data

---

### 7. ARCore для Android (`9791471`)

Реализован нативный platform channel для ARCore — полноценная замена заглушки на Android.

**Новые файлы (Kotlin):**
- `android/app/src/main/kotlin/com/example/wardrobe/ArCoreView.kt` — нативный `GLSurfaceView` + ARCore Session: инициализация, детектирование горизонтальных и вертикальных плоскостей, `EventChannel` для отправки плоскостей во Flutter, `MethodChannel` для управления (`resume/pause/reset`), дедупликация обновлений
- `android/app/src/main/kotlin/com/example/wardrobe/ArCorePlugin.kt` — `PlatformViewFactory`, регистрирует `ArCoreView` под типом `"wardrobe/arcore_view"`

**Изменения (Kotlin/Android):**
- `MainActivity.kt` — регистрация `ArCorePlugin` через `flutterEngine.platformViewsController.registry`
- `android/app/build.gradle.kts` — зависимость `com.google.ar:core:1.44.0`
- `AndroidManifest.xml` — добавлен `<uses-feature android:glEsVersion="0x00030000">` (OpenGL ES 3.0 требует ARCore)

**Изменения (Dart/Flutter):**
- `lib/services/ar_scan_service.dart` — добавлен `initAndroidChannels(viewId)`: подписка на `EventChannel` плоскостей ARCore, `onAndroidPlaneEvent` парсит Map с нативной стороны, `_onAndroidError` для обработки ошибок; `isSupported` теперь `true` на обеих платформах; добавлен класс-константа `ArCoreView` с именами каналов
- `lib/screens/floor_plan_screen.dart` — `_AndroidFallback` заменён на `_AndroidArCoreView` (`AndroidView`); при создании view вызывается `scanService.initAndroidChannels(viewId)`; баннер на стартовом экране обновлён с «в разработке» на «ARCore активен»; убран `AnimationController` (больше не нужен)

**Архитектура:**

```
Flutter (Dart)                      Android (Kotlin)
──────────────────────────────      ─────────────────────────────
AndroidView("wardrobe/arcore_view") ──► ArCorePlugin (factory)
                                              │
                                         ArCoreView (GLSurfaceView)
                                              │ ARCore Session
ArScanService.initAndroidChannels()          │
  EventChannel ◄─── planes stream ◄──────────┤
  MethodChannel ──► resume/pause/reset ──────►│
```

---

---

### 8. Экспорт плана в PNG и PDF

**Новые файлы:**
- `lib/services/export_service.dart` — статический сервис экспорта:
  - `exportPng(GlobalKey)` — рендерит `RepaintBoundary` в изображение через `RenderRepaintBoundary.toImage(pixelRatio: 3.0)`, сохраняет PNG во временную директорию
  - `exportPdf(ScanResult)` — строит PDF-документ через пакет `pdf`: векторный план (масштабированные прямоугольники горизонтальных плоскостей + линии стен), итоговая статистика, таблица поверхностей, timestamp и подпись
  - `share(ExportResult)` — передаёт файл в системный шит через `share_plus`

**Изменения:**
- `pubspec.yaml` — добавлены `pdf ^3.11.0`, `path_provider ^2.1.0`, `share_plus ^10.0.0`
- `lib/screens/floor_plan_screen.dart`:
  - `_FloorPlanScreenState` — добавлен `GlobalKey _planRepaintKey`, метод `_showExportSheet(share:)` открывает `ModalBottomSheet` с выбором формата; `_doExport` вызывает `ExportService` и показывает snackbar с именем файла
  - AppBar — кнопка «Поделиться» и новая кнопка «Скачать» активны при наличии плана; во время экспорта показывается `CircularProgressIndicator`
  - `_PlanView` — добавлены параметры `onSave` и `planRepaintKey`; `CustomPaint` обёрнут в `RepaintBoundary(key: planRepaintKey)` для PNG-рендера; кнопка «Сохранить» подключена к `onSave`
  - Новые виджеты `_ExportFormatSheet` и `_FormatTile` — bottomsheet выбора формата (PNG / PDF)

## Текущая структура проекта

```
lib/
├── main.dart
├── screens/
│   ├── home_screen.dart
│   ├── floor_plan_screen.dart         # AR-сканирование + экспорт PNG/PDF
│   ├── object_recognition_screen.dart
│   └── history_screen.dart
├── services/
│   ├── camera_service.dart
│   ├── object_detection_service.dart
│   ├── ar_scan_service.dart
│   ├── export_service.dart            # Экспорт плана в PNG и PDF
│   ├── app_state.dart
│   └── app_storage.dart
├── widgets/
│   └── camera_preview_widget.dart
└── theme/
    └── app_theme.dart

android/app/src/main/kotlin/com/example/wardrobe/
├── MainActivity.kt
├── ArCorePlugin.kt
└── ArCoreView.kt
```

---

---

### 9. Кастомная TFLite-модель для мебели

**Модель:** EfficientDet-Lite0 (TFHub, COCO 80 классов, 4.4 МБ) — распознаёт конкретные предметы интерьера: `chair`, `couch`, `bed`, `dining table`, `laptop`, `tv`, `refrigerator`, `oven`, `microwave`, `sink`, `potted plant`, `vase`, `clock`, `book` и др.

**Новые файлы:**
- `assets/ml/furniture_detector.tflite` — EfficientDet-Lite0 с встроенными метаданными ML Kit
- `assets/ml/furniture_labels.txt` — список COCO-классов для справки

**Изменения:**
- `pubspec.yaml` — добавлены `path: ^1.9.0`, регистрация assets (`assets/ml/`)
- `lib/services/object_detection_service.dart`:
  - Добавлен `enum DetectorMode { base, custom }`
  - `initialize([DetectorMode])` и `switchMode(DetectorMode)` — переключение детектора на лету
  - В режиме `custom`: `LocalObjectDetectorOptions` с `modelPath` (модель копируется из assets в `getTemporaryDirectory()` при первом запуске)
  - В режиме `base`: прежний `ObjectDetectorOptions` (встроенная ML Kit модель)
  - Расширен словарь локализации — охватывает все COCO-классы бытовых предметов (строчные `chair`, `couch`, `bed` и заглавные `Chair`, `Sofa` и т.д.)
  - `confidenceThreshold: 0.45` для кастомной модели (вместо 0.4 на base)
- `lib/screens/object_recognition_screen.dart`:
  - По умолчанию запускается в режиме `DetectorMode.custom`
  - Новый виджет `_ModelToggle` в AppBar — компактный чип «EfficientDet / Base» с переключением по тапу; при переключении поток останавливается, детектор пересоздаётся

## Текущая структура проекта

```
lib/
├── main.dart
├── screens/
│   ├── home_screen.dart
│   ├── floor_plan_screen.dart         # AR-сканирование + экспорт PNG/PDF
│   ├── object_recognition_screen.dart # ML Kit + EfficientDet-Lite0
│   └── history_screen.dart
├── services/
│   ├── camera_service.dart
│   ├── object_detection_service.dart  # Base + Custom TFLite режимы
│   ├── export_service.dart
│   ├── ar_scan_service.dart
│   ├── app_state.dart
│   └── app_storage.dart
├── widgets/
│   └── camera_preview_widget.dart
└── theme/
    └── app_theme.dart

assets/
└── ml/
    ├── furniture_detector.tflite      # EfficientDet-Lite0 (COCO 80, 4.4 МБ)
    └── furniture_labels.txt           # Список классов

android/app/src/main/kotlin/com/example/wardrobe/
├── MainActivity.kt
├── ArCorePlugin.kt
└── ArCoreView.kt
```

---

---

### 10. Онбординг (`OnboardingScreen`)

Экран приветствия показывается только при первом запуске. После завершения флаг сохраняется в `SharedPreferences` и онбординг больше не отображается.

**4 слайда:**

| # | Иконка | Тема |
|---|--------|------|
| 1 | `home_outlined` | Добро пожаловать в Wardrobe |
| 2 | `map_outlined` | Сканирование пространства (ARKit / ARCore) |
| 3 | `chair_outlined` | Распознавание мебели (EfficientDet-Lite) |
| 4 | `download_outlined` | Экспорт в PNG / PDF |

**Новые файлы:**
- `lib/screens/onboarding_screen.dart` — `PageView` из 4 слайдов; анимированные точки-индикаторы (активная расширяется в капсулу); кнопка «Далее» / «Начать» (AnimatedSwitcher); кнопка «Пропустить» скрывается на последнем слайде

**Изменения:**
- `lib/services/app_storage.dart` — ключ `onboarding_completed`, геттер и метод `completeOnboarding()`
- `lib/services/app_state.dart` — геттер `onboardingCompleted`, метод `completeOnboarding()`
- `lib/main.dart` — `home` определяется по `appState.onboardingCompleted`; `_OnboardingWrapper` вызывает `completeOnboarding()` и делает `pushReplacement` с fade-переходом на `HomeScreen`

## Текущая структура проекта

```
lib/
├── main.dart                          # Роутинг: онбординг → HomeScreen
├── screens/
│   ├── onboarding_screen.dart         # Первый запуск (4 слайда)
│   ├── home_screen.dart
│   ├── floor_plan_screen.dart         # AR-сканирование + экспорт PNG/PDF
│   ├── object_recognition_screen.dart # ML Kit + EfficientDet-Lite0
│   └── history_screen.dart
├── services/
│   ├── camera_service.dart
│   ├── object_detection_service.dart  # Base + Custom TFLite режимы
│   ├── export_service.dart            # Экспорт PNG / PDF
│   ├── ar_scan_service.dart           # ARKit iOS + ARCore Android
│   ├── app_state.dart                 # Глобальное состояние
│   └── app_storage.dart              # SharedPreferences
├── widgets/
│   └── camera_preview_widget.dart
└── theme/
    └── app_theme.dart

assets/
└── ml/
    ├── furniture_detector.tflite
    └── furniture_labels.txt

android/app/src/main/kotlin/com/example/wardrobe/
├── MainActivity.kt
├── ArCorePlugin.kt
└── ArCoreView.kt
```

---

---

## Баги и их исправления

### Баг 1 — сканирование заканчивается сразу после старта (`b1f4590`)

**Симптом:** нажимаешь «Начать сканирование» на Android — экран мгновенно возвращается в начальное состояние, план не строится.

**Причина:** цепочка событий при ошибке ARCore:

1. `ArCoreView.kt` не может инициализировать сессию (устройство не поддерживает ARCore, ARCore не установлен, или `requestInstall` вернул `INSTALL_REQUESTED`) → вызывает `sendError(code, message)`
2. `sendError` публикует событие с `code` в `EventChannel`
3. В `ArScanService._onAndroidError` вызывается `setError(message)` → `_isScanning = false` + `notifyListeners()`
4. `FloorPlanScreen._onScanUpdate` → `setState()` → `_buildBody` видит `isScanning == false` → рисует `_EmptyView`

Никакого сообщения пользователю не выводилось. Ошибка проглатывалась молча.

**Исправление:**

- `_onScanUpdate` в `FloorPlanScreen` проверяет `_scanService.errorMessage` и показывает `SnackBar` через `WidgetsBinding.addPostFrameCallback` (прямой вызов из `setState` запрещён):

```dart
void _onScanUpdate() {
  if (!mounted) return;
  final err = _scanService.errorMessage;
  if (err != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showSnackBar(context, err);
    });
  }
  setState(() {});
}
```

- `_EmptyView` получил необязательный параметр `errorMessage`; при наличии ошибки отображается красный баннер под описанием — виден сразу, не зависит от timing SnackBar.
- `_buildBody` передаёт `_scanService.errorMessage` в `_EmptyView`.

---

### Баг 2 — `InputImageConverterError: IllegalArgumentException` при распознавании (`b1f4590`)

**Симптом:** на Android при нажатии «Распознать» детектор выбрасывает исключение и не возвращает результатов. На iOS работает нормально.

**Причина:** неправильная конвертация `CameraImage` в `InputImage` для ML Kit.

Android камера отдаёт кадры в формате **YUV_420_888** — три отдельных плейна:
- Плейн 0: Y (яркость), размер `width × height`, stride может быть > width
- Плейн 1: U (Cb), размер `width/2 × height/2`, `pixelStride` обычно 2 (interleaved с V)
- Плейн 2: V (Cr), размер `width/2 × height/2`, `pixelStride` обычно 2

Старый код просто конкатенировал все три плейна через `WriteBuffer`:

```dart
// НЕПРАВИЛЬНО
final WriteBuffer allBytes = WriteBuffer();
for (final plane in image.planes) {
  allBytes.putUint8List(plane.bytes);
}
```

Это создавало буфер с неверным layout — Y‑плейн с padding-байтами (stride > width), затем U и V как отдельные массивы. ML Kit Custom Model (`LocalObjectDetectorOptions`) передаёт буфер в нативный конвертер, который ожидает **NV21** (Y без padding + чередующиеся VU байты) — отсюда `IllegalArgumentException`.

Встроенная base-модель (`ObjectDetectorOptions`) менее строга к формату, поэтому баг проявился только после переключения на кастомную TFLite-модель.

**Исправление:** ручная конвертация YUV_420_888 → NV21 в `_toInputImageAndroid()`:

```dart
mlkit.InputImage? _toInputImageAndroid(CameraImage image, rotation) {
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final nv21 = Uint8List(width * height + (width ~/ 2) * (height ~/ 2) * 2);

  // Y-плейн: копируем построчно, убирая padding (stride может быть > width)
  int idx = 0;
  for (int row = 0; row < height; row++) {
    nv21.setRange(idx, idx + width, yPlane.bytes, row * yPlane.bytesPerRow);
    idx += width;
  }

  // UV interleaved: чередуем V и U (NV21 = VU, не UV)
  for (int row = 0; row < height ~/ 2; row++) {
    for (int col = 0; col < width ~/ 2; col++) {
      final offset = row * uvRowStride + col * uvPixelStride;
      nv21[idx++] = vPlane.bytes[offset]; // V
      nv21[idx++] = uPlane.bytes[offset]; // U
    }
  }

  // bytesPerRow = width (без padding, NV21 плотный)
  return InputImage.fromBytes(bytes: nv21, metadata: ...nv21, bytesPerRow: width);
}
```

iOS (`BGRA8888`) — один плейн, padding нет — старый код оставлен без изменений.

### Баг 3 — `IllegalStateException: Context is not an Activity` при запуске ARCore (`e7c056d`)

**Симптом:** при открытии экрана сканирования на Android приложение падало или ARCore не инициализировался с ошибкой `Context is not an Activity`.

**Причина:** в `ArCoreView.kt` был метод `requireActivity()`, который пытался скастить `context` к `Activity`:

```kotlin
private fun requireActivity(): Activity {
    return (context as? Activity)
        ?: throw IllegalStateException("Context is not an Activity")
}
```

Этот каст всегда завершается неудачей. Flutter передаёт `PlatformView` не сам `Activity`, а `MutableContextWrapper` — специальную обёртку контекста. Она делегирует часть методов к `Activity` внутри, но `context instanceof Activity` возвращает `false`. Это стандартное поведение Flutter PlatformView на Android, не баг фреймворка.

`ArCoreApk.requestInstall()` требует именно `Activity` (не просто `Context`) для показа диалога установки ARCore — поэтому обойти каст было нельзя.

**Исправление:** `Activity` передаётся явно по цепочке при регистрации фабрики:

```
MainActivity (this: Activity)
  └─► ArCorePlugin(messenger, activity = this)
        └─► ArCoreView(context, messenger, viewId, activity)
              └─► ArCoreApk.requestInstall(activity, ...)  ✅
```

- `ArCorePlugin` получил параметр `activity: Activity` в конструкторе
- `ArCoreView` получил параметр `activity: Activity`, использует его вместо `requireActivity()`
- `MainActivity.configureFlutterEngine` передаёт `this` как `Activity`
- Метод `requireActivity()` удалён

`MainActivity` наследует `FlutterActivity extends Activity`, поэтому `this` всегда является корректным `Activity`.

### Версионирование и отображение версии в UI

**Правило:** версия поднимается в `pubspec.yaml` (`version: major.minor.patch+buildNumber`) с каждым релизным билдом. `buildNumber` — монотонно возрастающий счётчик.

**Изменения:**
- `pubspec.yaml` — версия `1.0.0+1` → `1.2.0+2`; добавлен `package_info_plus ^8.0.0`
- `lib/screens/home_screen.dart`:
  - `_DashboardTab` переведён из `StatelessWidget` в `StatefulWidget`
  - `initState` загружает `PackageInfo.fromPlatform()` асинхронно
  - AppBar title показывает `Wardrobe` + `v1.2.0` подзаголовком (появляется после загрузки)
  - Кнопка `info_outline` в AppBar открывает стандартный `showAboutDialog` с версией, build-номером, иконкой и кратким описанием возможностей
  - Вспомогательный виджет `_AboutRow` — строка с иконкой и текстом в About-диалоге

### Баг 4 — чёрный экран вместо камеры в ARCore (`e1d1855`)

**Симптом:** на Android после нажатия «Начать сканирование» вместо изображения с камеры отображался чёрный квадрат. Плоскости при этом могли детектироваться (данные приходили во Flutter), но пользователь не видел реальную картинку.

**Причина:** `session.setCameraTextureName(0)` — хардкоженный `0` не является валидным OpenGL-текстурным ID.

ARCore работает так: приложение выделяет OpenGL-текстуру типа `GL_TEXTURE_EXTERNAL_OES`, передаёт её ID в ARCore через `setCameraTextureName()`, и ARCore сам записывает в неё каждый кадр с камеры. Приложение затем рисует эту текстуру на экране. При `ID = 0` ARCore не знает куда писать — экран остаётся чёрным.

**Исправление:**

Добавлен полноценный OpenGL ES 2.0 рендер камеры:

1. **`createCameraTexture()`** — выделяет `GL_TEXTURE_EXTERNAL_OES` через `glGenTextures`, настраивает `CLAMP_TO_EDGE` и `LINEAR`-фильтрацию. Вызывается в `onSurfaceCreated`.

2. **`createShaderProgram()`** — компилирует два шейдера:
   - Вершинный: рисует full-screen quad (4 вершины, `TRIANGLE_STRIP`)
   - Фрагментный: `#extension GL_OES_EGL_image_external` + `samplerExternalOES` — единственный способ семплировать OES-текстуру

3. **`drawCameraFrame()`** — вызывается каждый кадр в `onDrawFrame` перед `session.update()`:
   - Биндит OES-текстуру на `GL_TEXTURE0`
   - Рисует quad с UV-координатами (Y перевёрнут: `v = 1 - v`, иначе картинка вверх ногами)

4. **`dispose()`** — `glDeleteTextures` + `glDeleteProgram` для предотвращения утечек GPU-ресурсов.

```
onSurfaceCreated:
  createCameraTexture()   → cameraTextureId = glGenTextures()
  createShaderProgram()   → компиляция шейдеров
  initArSession()

onDrawFrame:
  setCameraTextureName(cameraTextureId)  → ARCore пишет кадр
  session.update()
  drawCameraFrame()       → рисуем OES-текстуру на экран
  processPlanes(frame)    → отправляем плоскости во Flutter
```

### Баг 5 — `NullPointerException` в ML Kit при распознавании (`076ca33`)

**Симптом:** `PlatformException(InputImageConvertError, java.lang.NullPointerException: Attempt to invoke virtual method 'java.lang.Class java.lang.Object.getClass()' on null object reference, null, null)` при нажатии «Распознать» на Android.

**Причина:** `CameraService` инициализировал контроллер с `ImageFormatGroup.jpeg` на всех платформах:

```dart
imageFormatGroup: ImageFormatGroup.jpeg,  // НЕПРАВИЛЬНО для Android
```

На Android `imageStream` с форматом `jpeg` отдаёт **один плейн** с JPEG-кодированными байтами. Отдельных Y/U/V плейнов нет — `image.planes[1]` и `image.planes[2]` пустые или недоступны.

NV21-конвертер в `_toInputImageAndroid()` обращался к `planes[1]` и `planes[2]` без проверки → передавал пустой/нулевой буфер в ML Kit → `InputImageConverter.java` вызывал `Objects.requireNonNull(imageData.get("bytes"))` на `null` → `NullPointerException`.

**Цепочка:**
```
imageStream (jpeg) → один JPEG-плейн
→ _toInputImageAndroid: planes[1].bytes пустой
→ nv21 буфер частично пустой
→ InputImage.fromBytes(bytes: nv21, ...)
→ Java: Objects.requireNonNull(imageData.get("bytes")) → NPE
```

**Исправление:**

1. **`camera_service.dart`** — раздельный `ImageFormatGroup` по платформе:

```dart
imageFormatGroup: Platform.isAndroid
    ? ImageFormatGroup.yuv420   // три отдельных плейна Y/U/V
    : ImageFormatGroup.bgra8888, // iOS: один BGRA плейн
```

`yuv420` на Android → `imageStream` отдаёт `YUV_420_888` с тремя корректными плейнами. NV21-конвертер работает правильно.

Заодно снижено разрешение с `ResolutionPreset.high` до `medium` (~720p) — уменьшает размер буфера и нагрузку на platform channel.

2. **`object_detection_service.dart`** — добавлены защитные проверки в `_toInputImageAndroid`:
   - `if (image.planes.length < 3) return null`
   - `if (yPlane.bytes.isEmpty || ...) return null`
   - `uvPixelStride` fallback изменён с `?? 1` на `?? 2` (реальный stride interleaved UV-плейна)
   - Bounds check на `uvOffset` при копировании VU-байт

---

## Все пункты плана выполнены

| # | Функция | Статус |
|---|---------|--------|
| 1 | UI-прототип | ✅ |
| 2 | Интеграция камеры | ✅ |
| 3 | ML Kit распознавание | ✅ |
| 4 | Android APK / iOS .app сборки | ✅ |
| 5 | Персистентность данных | ✅ |
| 6 | ARKit (iOS) | ✅ |
| 7 | ARCore (Android) | ✅ |
| 8 | Экспорт PNG / PDF | ✅ |
| 9 | EfficientDet-Lite0 TFLite | ✅ |
| 10 | Онбординг | ✅ |

