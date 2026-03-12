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

    // Master controller: 2.5s total animation
    _masterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Particle controller: continuous subtle animation
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _initAnimations();
    _startAnimation();
  }

  void _initAnimations() {
    // Logo: 0-800ms with elastic bounce
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.0, 0.32, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
      ),
    );
    _logoGlow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.1, 0.4, curve: Curves.easeOut),
      ),
    );

    // Ring 1: starts at 200ms
    _ring1Scale = Tween<double>(begin: 0.8, end: 1.5).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.08, 0.48, curve: Curves.easeOut),
      ),
    );
    _ring1Opacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.08, 0.48, curve: Curves.easeOut),
      ),
    );

    // Ring 2: starts at 400ms
    _ring2Scale = Tween<double>(begin: 0.8, end: 1.5).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.16, 0.56, curve: Curves.easeOut),
      ),
    );
    _ring2Opacity = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.16, 0.56, curve: Curves.easeOut),
      ),
    );

    // App name: 300-800ms
    _nameOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.12, 0.32, curve: Curves.easeOut),
      ),
    );
    _nameSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.12, 0.32, curve: Curves.easeOutCubic),
      ),
    );

    // Tagline: 500-1000ms
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.2, 0.4, curve: Curves.easeOut),
      ),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.2, 0.4, curve: Curves.easeOutCubic),
      ),
    );

    // Background gradient shift
    _gradientShift = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: Curves.easeInOut,
      ),
    );

    // Exit: 2200-2500ms
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.88, 1.0, curve: Curves.easeIn),
      ),
    );
    _exitScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.88, 1.0, curve: Curves.easeIn),
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
        _buildParticle(0.2, 0.15, 8, 0.0),
        _buildParticle(0.8, 0.25, 6, 0.3),
        _buildParticle(0.15, 0.7, 10, 0.6),
        _buildParticle(0.85, 0.65, 7, 0.2),
        _buildParticle(0.5, 0.85, 5, 0.8),
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
    final opacity = (0.1 + 0.15 * (1 - (phase - 0.5).abs() * 2)) *
        _logoOpacity.value;

    return Positioned(
      left: MediaQuery.of(context).size.width * left,
      top: MediaQuery.of(context).size.height * top,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ring 1
          Transform.scale(
            scale: _ring1Scale.value,
            child: Opacity(
              opacity: _ring1Opacity.value,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          // Ring 2
          Transform.scale(
            scale: _ring2Scale.value,
            child: Opacity(
              opacity: _ring2Opacity.value,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          // Logo
          Transform.scale(
            scale: _logoScale.value,
            child: Opacity(
              opacity: _logoOpacity.value,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary,
                      Color(0xFFFF6B81),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(
                        alpha: 0.4 * _logoGlow.value,
                      ),
                      blurRadius: 30 * _logoGlow.value,
                      spreadRadius: 5 * _logoGlow.value,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_rounded,
                  size: 50,
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
        child: const Text(
          '小颜圈',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: 6,
            height: 1.2,
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
        child: const Text(
          '创作者的素材灵感库',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
