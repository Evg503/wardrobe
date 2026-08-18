# Wardrobe — История разработки

## Стек технологий

- **Flutter 3.47.0** / Dart — кроссплатформенный фреймворк (iOS + Android)
- **Material 3** — дизайн-система
- **camera ^0.11.0** — живой видеопоток с камеры
- **google_mlkit_object_detection ^0.14.0** — распознавание объектов на устройстве
- **arkit_plugin ^1.5.0** — AR-сканирование планировки (iOS)
- **shared_preferences ^2.3.0** — локальное хранилище данных
- **vector_math ^2.1.4** — математика для AR

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

## Текущая структура проекта

```
lib/
├── main.dart                          # Точка входа, инициализация AppState
├── screens/
│   ├── home_screen.dart               # Дашборд + NavigationBar (4 вкладки)
│   ├── floor_plan_screen.dart         # AR-сканирование (ARKit iOS / заглушка Android)
│   ├── object_recognition_screen.dart # ML Kit распознавание объектов
│   └── history_screen.dart            # История сессий
├── services/
│   ├── camera_service.dart            # Управление камерой
│   ├── object_detection_service.dart  # ML Kit детектор
│   ├── ar_scan_service.dart           # AR-сканирование, модели плоскостей
│   ├── app_state.dart                 # Глобальное состояние (InheritedNotifier)
│   └── app_storage.dart              # Слой хранения (shared_preferences)
├── widgets/
│   └── camera_preview_widget.dart     # Переиспользуемый превью камеры
└── theme/
    └── app_theme.dart                 # Централизованная тема
```

---

## Что планируется дальше

- **ARCore для Android** — нативный platform channel или актуальный плагин
- **Экспорт плана** — сохранение в PDF/PNG
- **Улучшение ML Kit** — кастомная TFLite-модель для мебели (обучить через Roboflow)
- **Онбординг** — первый запуск с объяснением функций
