# Wardrobe

Мобильное приложение для AR-сканирования плана квартиры и распознавания предметов мебели через камеру устройства.

## Возможности

- **Сканирование плана** — ARKit (iOS) / ARCore (Android), детектирование горизонтальных и вертикальных плоскостей
- **Распознавание мебели** — EfficientDet-Lite0 (COCO 80 классов), работает офлайн
- **Экспорт** — сохранение плана в PNG или PDF, шаринг через системный диалог
- **История** — хранение сессий сканирования и распознавания

## Требования к среде

| Компонент | Версия |
|-----------|--------|
| Flutter | 3.47.0+ |
| Dart SDK | ≥ 3.13.0 |
| Android SDK | compileSdk 36, minSdk 24 |
| iOS Deployment Target | 16.0 |
| Xcode (только macOS) | 15+ |
| CocoaPods (только macOS) | 1.15+ |
| Java / Android Studio | JDK 17+ |

---

## Сборка на macOS

macOS — единственная платформа, на которой можно собрать **и Android, и iOS**.

### 1. Установить Flutter

```bash
# Через Homebrew
brew install --cask flutter

# Или вручную: скачать архив с flutter.dev, распаковать, добавить в PATH
export PATH="$HOME/flutter/bin:$PATH"
```

Проверить:

```bash
flutter doctor
```

Все пункты должны быть без ошибок (кроме опциональных).

### 2. Установить CocoaPods (нужен для iOS)

```bash
# Homebrew Ruby (рекомендуется — системный Ruby 2.6 не подходит)
brew install ruby
/opt/homebrew/bin/gem install cocoapods
```

Проверить:

```bash
/opt/homebrew/bin/pod --version  # ожидается 1.15+
```

### 3. Клонировать репозиторий и установить зависимости

```bash
git clone https://github.com/Evg503/wardrobe.git
cd wardrobe
flutter pub get
```

### 4. Сборка Android APK

```bash
flutter build apk --release
```

Артефакт: `build/app/outputs/flutter-apk/app-release.apk`

Для сборки под конкретный ABI (меньший размер):

```bash
flutter build apk --release --target-platform android-arm64
```

### 5. Сборка iOS

```bash
cd ios
/opt/homebrew/bin/pod install
cd ..
flutter build ios --release --no-codesign
```

Артефакт: `build/ios/Release-iphoneos/Runner.app`

> `--no-codesign` — сборка без подписи. Для установки на реальное устройство нужно открыть `ios/Runner.xcworkspace` в Xcode, настроить Team и подписать вручную.

Запаковать для передачи:

```bash
cd build/ios/Release-iphoneos
zip -r wardrobe.zip Runner.app
```

---

## Сборка на Windows

На Windows можно собрать **только Android APK**. iOS-сборка на Windows невозможна (ограничение Apple).

### 1. Установить Flutter

Скачать Flutter SDK с [flutter.dev](https://flutter.dev/docs/get-started/install/windows), распаковать в `C:\flutter` (путь не должен содержать пробелов и спецсимволов).

Добавить в PATH:

```
C:\flutter\bin
```

Проверить:

```powershell
flutter doctor
```

### 2. Установить Android Studio и SDK

1. Скачать [Android Studio](https://developer.android.com/studio)
2. При установке включить **Android SDK**, **Android SDK Platform-Tools**
3. В Android Studio → SDK Manager установить:
   - Android SDK Platform 36
   - Android SDK Build-Tools 36
   - NDK (нужная версия подтянется автоматически при сборке)
4. Принять лицензии:

```powershell
flutter doctor --android-licenses
```

### 3. Клонировать и установить зависимости

```powershell
git clone https://github.com/Evg503/wardrobe.git
cd wardrobe
flutter pub get
```

### 4. Сборка Android APK

```powershell
flutter build apk --release
```

Артефакт: `build\app\outputs\flutter-apk\app-release.apk`

> Если Gradle падает с ошибкой про JDK — убедитесь, что используется JDK 17. Android Studio поставляет его в `%APPDATA%\Local\Android\Sdk\...` или используйте `JAVA_HOME`.

---

## Сборка на Linux

На Linux можно собрать **только Android APK**. iOS-сборка на Linux невозможна.

### 1. Установить Flutter

```bash
# Snap (Ubuntu/Debian)
sudo snap install flutter --classic

# Или вручную
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
```

Проверить:

```bash
flutter doctor
```

### 2. Установить Java и Android SDK

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install openjdk-17-jdk

# Скачать Command Line Tools с developer.android.com/studio#command-line-tools-only
mkdir -p ~/android-sdk/cmdline-tools
unzip commandlinetools-linux-*.zip -d ~/android-sdk/cmdline-tools
mv ~/android-sdk/cmdline-tools/cmdline-tools ~/android-sdk/cmdline-tools/latest

export ANDROID_HOME=$HOME/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools
```

Установить компоненты SDK:

```bash
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter doctor --android-licenses
```

### 3. Клонировать и установить зависимости

```bash
git clone https://github.com/Evg503/wardrobe.git
cd wardrobe
flutter pub get
```

### 4. Сборка Android APK

```bash
flutter build apk --release
```

Артефакт: `build/app/outputs/flutter-apk/app-release.apk`

---

## Установка на устройство

### Android

Включить режим разработчика и USB-отладку на устройстве, подключить кабелем:

```bash
# Проверить что устройство видно
adb devices

# Установить APK
adb install build/app/outputs/flutter-apk/app-release.apk
```

Или просто скопировать APK на устройство и открыть файловым менеджером (нужно разрешить установку из неизвестных источников).

### iOS

Требует macOS + Xcode + Apple Developer аккаунт:

1. Открыть `ios/Runner.xcworkspace` в Xcode
2. В **Signing & Capabilities** выбрать Team
3. Подключить iPhone, выбрать его как таргет
4. Product → Run (или `⌘R`)

---

## Быстрый старт для разработки

```bash
# Запуск на подключённом устройстве или эмуляторе
flutter run

# Запуск с горячей перезагрузкой
flutter run --debug

# Проверка кода
flutter analyze

# Тесты
flutter test
```

---

## Структура проекта

```
lib/
├── main.dart                          # Точка входа, роутинг онбординг → главный экран
├── screens/
│   ├── onboarding_screen.dart         # Первый запуск
│   ├── home_screen.dart               # Дашборд + навигация
│   ├── floor_plan_screen.dart         # AR-сканирование + экспорт
│   ├── object_recognition_screen.dart # Распознавание предметов
│   └── history_screen.dart            # История сессий
├── services/
│   ├── camera_service.dart
│   ├── object_detection_service.dart  # ML Kit + EfficientDet-Lite0
│   ├── export_service.dart            # PNG / PDF экспорт
│   ├── ar_scan_service.dart           # ARKit / ARCore
│   ├── app_state.dart
│   └── app_storage.dart
├── widgets/
│   └── camera_preview_widget.dart
└── theme/
    └── app_theme.dart

assets/ml/
├── furniture_detector.tflite          # EfficientDet-Lite0 (4.4 МБ)
└── furniture_labels.txt

android/app/src/main/kotlin/com/example/wardrobe/
├── MainActivity.kt
├── ArCorePlugin.kt                    # PlatformView factory
└── ArCoreView.kt                      # ARCore session + channels
```

---

## Известные ограничения

- **ARCore на Android** требует устройство с поддержкой ARCore ([список](https://developers.google.com/ar/devices)) и установленного Google Play Services for AR
- **ARKit на iOS** требует iPhone с iOS 16.0+; LiDAR (iPhone 12 Pro+) даёт заметно лучший результат
- iOS-сборка без codesign (`--no-codesign`) не устанавливается через ADB/iTunes напрямую — только через Xcode
- Предупреждение `KGP` при Android-сборке от плагинов `camera_android_camerax` и `share_plus` — некритично, сборка проходит успешно
