import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/colors.dart';
import '../../../core/auth/auth_provider.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with TickerProviderStateMixin {
  late final AnimationController _masterController;
  late final AnimationController _particleController;

  // Logo animations
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoGlow;

  // Text animations
  late final Animation<double> _nameOpacity;
  late final Animation<Offset> _nameSlide;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineSlide;

  // Ring animations (multiple rings)
  late final Animation<double> _ring1Scale;
  late final Animation<double> _ring1Opacity;
  late final Animation<double> _ring2Scale;
  late final Animation<double> _ring2Opacity;

  // Background gradient animation
  late final Animation<double> _gradientShift;

  // Exit animation
  late final Animation<double> _exitOpacity;
  late final Animation<double> _exitScale;

  @override
  void initState() {
    super.initState();

    // Master controller: 2.8s total animation (slightly longer for better pacing)
    _masterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    // Particle controller: continuous subtle animation
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _initAnimations();
    _startAnimation();
  }

  void _initAnimations() {
    // Logo: 0-900ms with stronger elastic bounce
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.0, 0.36, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.0, 0.24, curve: Curves.easeOut),
      ),
    );
    _logoGlow = Tween<double>(begin: 0.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.1, 0.5, curve: Curves.easeInOut),
      ),
    );

    // Ring 1: starts at 150ms, faster and more dramatic
    _ring1Scale = Tween<double>(begin: 0.7, end: 1.8).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.06, 0.5, curve: Curves.easeOut),
      ),
    );
    _ring1Opacity = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.06, 0.5, curve: Curves.easeIn),
      ),
    );

    // Ring 2: starts at 300ms, overlapping with ring 1
    _ring2Scale = Tween<double>(begin: 0.7, end: 1.8).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.12, 0.56, curve: Curves.easeOut),
      ),
    );
    _ring2Opacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.12, 0.56, curve: Curves.easeIn),
      ),
    );

    // App name: 250-700ms, faster entrance
    _nameOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.1, 0.28, curve: Curves.easeOut),
      ),
    );
    _nameSlide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.1, 0.28, curve: Curves.easeOutCubic),
      ),
    );

    // Tagline: 400-900ms
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.16, 0.36, curve: Curves.easeOut),
      ),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.16, 0.36, curve: Curves.easeOutCubic),
      ),
    );

    // Background gradient shift
    _gradientShift = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: Curves.easeInOut,
      ),
    );

    // Exit: 2400-2800ms (last 400ms)
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.86, 1.0, curve: Curves.easeInCubic),
      ),
    );
    _exitScale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.86, 1.0, curve: Curves.easeInCubic),
      ),
    );
  }

  Future<void> _startAnimation() async {
    await _masterController.forward();
    if (!mounted) return;
    _navigate();
  }

  void _navigate() {
    final authStatus = ref.read(authProvider).status;
    if (authStatus == AuthStatus.unauthenticated) {
      context.go('/login');
    } else {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _masterController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_masterController, _particleController]),
        builder: (context, _) => Opacity(
          opacity: _exitOpacity.value,
          child: Transform.scale(
            scale: _exitScale.value,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(
                      Colors.white,
                      const Color(0xFFFFF5F6),
                      _gradientShift.value * 0.5,
                    )!,
                    Color.lerp(
                      const Color(0xFFFFF5F6),
                      const Color(0xFFFFF0F2),
                      _gradientShift.value,
                    )!,
                    Color.lerp(
                      const Color(0xFFFFF0F2),
                      AppColors.primaryLight,
                      _gradientShift.value,
                    )!,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: SafeArea(
                child: Stack(
                  children: [
                    // Floating particles
                    _buildParticles(),
                    // Main content
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLogoSection(),
                          const SizedBox(height: 32),
                          _buildAppName(),
                          const SizedBox(height: 12),
                          _buildTagline(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParticles() {
    return Stack(
      children: [
        _buildParticle(0.15, 0.12, 10, 0.0),
        _buildParticle(0.85, 0.18, 7, 0.3),
        _buildParticle(0.12, 0.68, 12, 0.6),
        _buildParticle(0.88, 0.72, 8, 0.2),
        _buildParticle(0.5, 0.88, 6, 0.8),
        _buildParticle(0.25, 0.35, 5, 0.4),
        _buildParticle(0.75, 0.45, 9, 0.7),
      ],
    );
  }

  Widget _buildParticle(
    double left,
    double top,
    double size,
    double phaseOffset,
  ) {
    final phase = (_particleController.value + phaseOffset) % 1.0;
    // 更强的呼吸效果
    final opacity = (0.15 + 0.25 * (1 - (phase - 0.5).abs() * 2)) *
        _logoOpacity.value;
    // 添加轻微的缩放动画
    final scale = 0.8 + 0.4 * (1 - (phase - 0.5).abs() * 2);

    return Positioned(
      left: MediaQuery.of(context).size.width * left,
      top: MediaQuery.of(context).size.height * top,
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.8),
                  AppColors.primary.withValues(alpha: 0.2),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ring 1 - 更大的扩散效果
          Transform.scale(
            scale: _ring1Scale.value,
            child: Opacity(
              opacity: _ring1Opacity.value,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
          // Ring 2 - 延迟的第二波扩散
          Transform.scale(
            scale: _ring2Scale.value,
            child: Opacity(
              opacity: _ring2Opacity.value,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary,
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ),
          // Logo with enhanced glow
          Transform.scale(
            scale: _logoScale.value,
            child: Opacity(
              opacity: _logoOpacity.value,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary,
                      Color(0xFFFF6B81),
                      Color(0xFFFF8FA3),
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(
                        alpha: 0.5 * _logoGlow.value,
                      ),
                      blurRadius: 40 * _logoGlow.value,
                      spreadRadius: 8 * _logoGlow.value,
                    ),
                    BoxShadow(
                      color: const Color(0xFFFF6B81).withValues(
                        alpha: 0.3 * _logoGlow.value,
                      ),
                      blurRadius: 60 * _logoGlow.value,
                      spreadRadius: 12 * _logoGlow.value,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_rounded,
                  size: 56,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppName() {
    return SlideTransition(
      position: _nameSlide,
      child: Opacity(
        opacity: _nameOpacity.value,
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              AppColors.textPrimary,
              Color(0xFF333333),
            ],
          ).createShader(bounds),
          child: const Text(
            '小颜圈',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 8,
              height: 1.2,
              shadows: [
                Shadow(
                  color: Color(0x20000000),
                  offset: Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagline() {
    return SlideTransition(
      position: _taglineSlide,
      child: Opacity(
        opacity: _taglineOpacity.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.08),
                AppColors.primary.withValues(alpha: 0.12),
                AppColors.primary.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '创作者的素材灵感库',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              letterSpacing: 2.5,
            ),
          ),
        ),
      ),
    );
  }
}
