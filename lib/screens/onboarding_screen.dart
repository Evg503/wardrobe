import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Данные одного слайда онбординга.
class _OnboardingPage {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String description;

  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.description,
  });
}

/// Экран онбординга — показывается только при первом запуске.
/// После нажатия «Начать» вызывает [onComplete] и больше не отображается.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pages = [
    _OnboardingPage(
      icon: Icons.home_outlined,
      iconColor: AppTheme.primary,
      iconBg: Color(0xFFE8F5EE),
      title: 'Добро пожаловать\nв Wardrobe',
      description:
          'Приложение для сканирования плана квартиры\n'
          'и автоматического распознавания мебели.',
    ),
    _OnboardingPage(
      icon: Icons.map_outlined,
      iconColor: Color(0xFF2979FF),
      iconBg: Color(0xFFE3EEFF),
      title: 'Сканируйте\nпространство',
      description:
          'Направьте камеру на комнату — приложение\n'
          'обнаружит поверхности через ARKit (iOS)\n'
          'или ARCore (Android) и построит план.',
    ),
    _OnboardingPage(
      icon: Icons.chair_outlined,
      iconColor: Color(0xFF7B1FA2),
      iconBg: Color(0xFFF3E5F5),
      title: 'Распознавайте\nмебель',
      description:
          'EfficientDet-Lite определяет диваны, кресла,\n'
          'кровати, столы, технику и декор прямо\n'
          'на устройстве — без интернета.',
    ),
    _OnboardingPage(
      icon: Icons.download_outlined,
      iconColor: Color(0xFF00897B),
      iconBg: Color(0xFFE0F2F1),
      title: 'Экспортируйте\nрезультат',
      description:
          'Сохраняйте план в PNG или PDF,\n'
          'делитесь через мессенджеры, почту\n'
          'или облачные хранилища.',
    ),
  ];

  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
    }
  }

  void _skip() => widget.onComplete();

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Кнопка «Пропустить»
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 16),
                child: AnimatedOpacity(
                  opacity: isLast ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    onPressed: isLast ? null : _skip,
                    child: Text(
                      'Пропустить',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Слайды
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) =>
                    _PageSlide(page: _pages[index]),
              ),
            ),

            // Индикаторы + кнопка
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: Column(
                children: [
                  // Точки-индикаторы
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => _DotIndicator(active: i == _currentPage),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Кнопка «Далее» / «Начать»
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          isLast ? 'Начать' : 'Далее',
                          key: ValueKey(isLast),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Один слайд ────────────────────────────────────────────────────────────────

class _PageSlide extends StatelessWidget {
  final _OnboardingPage page;

  const _PageSlide({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Иконка в круге
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: page.iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 72, color: page.iconColor),
          ),
          const SizedBox(height: 48),

          // Заголовок
          Text(
            page.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  height: 1.3,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Описание
          Text(
            page.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.65,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Точка-индикатор ───────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  final bool active;

  const _DotIndicator({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active
            ? AppTheme.primary
            : AppTheme.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
