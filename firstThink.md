# Размышления: технологии для приложения

## Построение плана квартиры по камере телефона

### iOS (нативные SDK)

#### Apple RoomPlan — лучший вариант
- Требует iOS 16+, LiDAR (iPhone 12 Pro и новее, iPad Pro с LiDAR)
- Распознаёт стены, двери, окна, мебель с размерами — сразу в структурированном виде
- Вывод: USD/USDZ (открывается в AutoCAD, Shapr3D и др.)
- Поддержка мультикомнатного сканирования через `StructureBuilder`
- Цена: бесплатно (Apple Developer Program, $99/год)

#### Apple ARKit
- Лежит в основе RoomPlan; даёт «сырую» геометрию комнаты
- Нет готового вывода плана — нужна своя логика конвертации
- Работает и без LiDAR, но с меньшей точностью

### Android

Прямого аналога RoomPlan нет. Лучший вариант:

#### Google ARCore — Depth API
- Глубина через фотограмметрию (работает без ToF-сенсора)
- На устройствах с ToF (Samsung S21 Ultra, Sony Xperia) — значительно точнее
- Нет готового плана: нужно самостоятельно обрабатывать point cloud
- Требует значительной кастомной разработки (RANSAC, polygon conversion и т.д.)

### Кроссплатформенные решения

| SDK | Платформа | Особенности |
|---|---|---|
| Unity AR Foundation | iOS + Android | Наиболее зрелое решение, C#, единый API над ARKit/ARCore |
| arkit_plugin | Flutter/iOS | Активно поддерживается |
| arcore_flutter_plugin | Flutter/Android | Поддерживается слабее |
| ViroReact | React Native | Не рекомендуется — слабая поддержка |

### SaaS/API (без написания логики сканирования)

#### Matterport API
- Полноценная платформа: сканирование → 2D план как сервис
- Приложение на iOS использует RoomPlan под капотом
- GraphQL Model API, Showcase SDK (JavaScript)
- Цена: от $9.99/мес, экспорт плана — платный аддон

#### Polycam Pro API
- LiDAR-сканирование + фотограмметрия, экспорт DXF/PDF
- API доступен для enterprise, цены по запросу

### Ключевые ограничения

- Истинная автоматическая генерация 2D плана без LiDAR — сложная задача CV
- Все non-LiDAR подходы (ARCore depth-from-motion, фотограмметрия) дают зашумлённую геометрию
- LiDAR устройства (Apple RoomPlan) или аппаратные глубинные сенсоры — практический путь к надёжному результату

---

## Распознавание предметов по камере телефона

### iOS (нативные)

#### Apple Vision + Core ML
- Использует Neural Engine (ANE) → задержка < 10 мс
- Распознаёт объекты, лица, текст, позы тела
- Полностью офлайн, бесплатно
- Нужны модели в формате `.mlmodel` (конвертируются из TF/PyTorch через Core ML Tools)
- Лучшая производительность на Apple Silicon

### Android + iOS (кроссплатформенные)

#### Google ML Kit — Object Detection
- Работает на iOS и Android, бесплатно
- Из коробки: 5 категорий (еда, растения, одежда, техника, места)
- Поддерживает кастомные TFLite-модели
- Отслеживание до 5 объектов в кадре в реальном времени
- Интеграция с Firebase для загрузки моделей OTA

#### TensorFlow Lite (LiteRT)
- Универсальный runtime для on-device инференса
- Поддерживает MobileNet, EfficientDet, YOLO и другие
- GPU-ускорение (2–5x быстрее CPU), полностью офлайн
- GPU Delegate, NNAPI (Android), Core ML Delegate (iOS), Hexagon DSP
- Бесплатно, Apache 2.0

#### PyTorch Mobile / ExecuTorch
- Современное edge-решение от PyTorch
- Экспорт через `torch.export()` → `.pte` формат
- XNNPACK backend для ARM, поддержка Qualcomm и Apple ANE
- Удобно для команд, уже использующих PyTorch

#### ONNX Runtime Mobile (Microsoft)
- Поддерживает модели из PyTorch, TensorFlow, scikit-learn
- iOS + Android, Core ML / NNAPI провайдеры

### Готовые модели для встраивания

#### YOLO (Ultralytics)
- Лучшее соотношение скорость/точность для реального времени
- Задачи: детекция, сегментация, pose estimation, OBB, трекинг
- Экспорт в TFLite, CoreML, ONNX, TensorRT
- Лицензия: AGPL-3.0 (бесплатно для open-source, коммерческая лицензия для продакшена)
- YOLO11n: ~30+ fps на мобильных устройствах

#### EfficientDet-Lite (Google)
- Хороший баланс точность/размер для мобильных (~4–10 МБ)
- EfficientDet-Lite2 — популярный компромисс
- Хорошо поддерживается в TFLite

#### MobileNet + SSD
- Минимальный размер (~6 МБ), 80 классов COCO
- Подходит для устройств с очень ограниченными ресурсами

### Фреймворки

#### MediaPipe (Google)
- Готовые пайплайны: детекция объектов, рук, лица, позы тела
- iOS, Android, Web, Python; есть `mediapipe_flutter`
- Task-based API, real-time video pipeline из коробки

#### OpenCV (с DNN-модулем)
- Классическое CV + инференс YOLO/SSD через ONNX
- Хорошо для препроцессинга изображений
- C++/Python/Java биндинги; `opencv4nodejs`, `flutter_opencv`

#### Roboflow Inference
- Управляемый инференс для кастомных YOLO-моделей
- `roboflow-swift` для iOS
- Удобен для быстрого прототипирования с кастомным датасетом

### Кроссплатформенные фреймворки

- **React Native:** `react-native-vision-camera` + `react-native-fast-tflite`
- **Flutter:** `google_mlkit_object_detection` или `tflite_flutter`
- **Unity:** Unity Sentis (ONNX) + ARFoundation

### Облачные API

| API | Бесплатно | Цена |
|---|---|---|
| Google Cloud Vision | 1 000 запросов/мес | $1.50 / 1 000 |
| AWS Rekognition | 1 000 запросов/мес (12 мес) | $0.001 / запрос |
| Azure Computer Vision | 5 000 запросов/мес | ~$1 / 1 000 |

Облако не подходит для распознавания в реальном времени — задержка 100–800 мс.

### Ключевые наблюдения

- On-device почти всегда предпочтительнее для реального времени
- YOLO → TFLite экспорт — самый распространённый production-паттерн для кастомной детекции
- Core ML на iOS стабильно быстрее TFLite на Apple Silicon благодаря Neural Engine
- ML Kit — самый быстрый путь к рабочему коду, но без кастомизации категорий
