# Wardrobe — История разработки

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

