import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../providers/session_provider.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/buttons.dart';

/// Loose email shape check; the server re-validates and normalises.
final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// The two email/password modes. Phone + OTP exists in the repository but is
/// intentionally not surfaced on the first-launch screen for now.
enum _AuthIntent { signIn, signUp }

/// Email + password sign-in / account creation, the simple first-launch path.
///
/// On success the [SessionController] flips to a signed-in session and the
/// session-driven app flow routes onward; this screen does not navigate itself.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _AuthIntent _intent = _AuthIntent.signIn;
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isSignUp => _intent == _AuthIntent.signUp;

  void _setIntent(_AuthIntent intent) {
    setState(() {
      _intent = intent;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final notifier = ref.read(sessionControllerProvider.notifier);
    try {
      // Success updates the session provider; AppFlow rebuilds past this
      // screen, so there is nothing to navigate to here.
      if (_isSignUp) {
        await notifier.signUp(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await notifier.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      if (mounted) setState(() => _submitting = false);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not reach the server. Check your connection and try again.';
        });
      }
    }
  }

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email.';
    if (!_emailPattern.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter your password.';
    if (_isSignUp && v.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  String? _validateName(String? value) {
    if (!_isSignUp) return null;
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Tell us your name.';
    if (v.length < 2) return 'That name looks too short.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.paddingScreen),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                // Logo
                const Center(child: BrandMark(size: 80)),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _isSignUp ? 'Create your account' : 'Welcome back',
                  style: AppTextStyles.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _isSignUp
                      ? 'Join DineCircle to book tables and host dinners.'
                      : 'Sign in to pick up where you left off.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),

                SegmentedButton<_AuthIntent>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _AuthIntent.signIn,
                      label: Text('Sign in'),
                    ),
                    ButtonSegment(
                      value: _AuthIntent.signUp,
                      label: Text('Create account'),
                    ),
                  ],
                  selected: {_intent},
                  onSelectionChanged: (selection) =>
                      _setIntent(selection.first),
                ),
                const SizedBox(height: AppSpacing.xl),

                if (_isSignUp) ...[
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'Alex Rivera',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.mail_rounded),
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: AppSpacing.lg),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: [
                    _isSignUp
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                      ),
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                    ),
                  ),
                  validator: _validatePassword,
                  onFieldSubmitted: (_) => _submit(),
                ),

                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  text: _isSignUp ? 'Create Account' : 'Sign In',
                  isLoading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => _setIntent(
                            _isSignUp ? _AuthIntent.signIn : _AuthIntent.signUp,
                          ),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : 'New to DineCircle? Create an account',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
