import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/dinner.dart';
import '../../models/booking.dart';
import '../../api/api_exception.dart';
import '../../providers/users_provider.dart';
import '../../widgets/buttons.dart';

/// Checkout screen - simplified booking flow (Phase 2a: Stripe removed)
/// Select Seats → Guest Info → Review → Confirm
class CheckoutScreen extends ConsumerStatefulWidget {
  final Dinner dinner;
  final void Function(Booking)? onComplete;

  const CheckoutScreen({super.key, required this.dinner, this.onComplete});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  int _seats = 1;
  int _currentStep = 0; // 0=seats, 1=guest info, 2=review+confirm
  bool _submitting = false;

  // Guest info
  final _nameController = TextEditingController();
  final _emailController = TextEditingController(text: 'alex@example.com');
  final _phoneController = TextEditingController(text: '+1 (415) 555-0101');
  final _notesController = TextEditingController();

  // Promo code
  final _promoController = TextEditingController();
  bool _promoApplied = false;
  String? _promoError;

  // Available promo codes (mock)
  static const _validPromos = {
    'FOODIE5': 5.0,
    'WELCOME10': 10.0,
    'DINE20': 20.0,
    'VIP15': 15.0,
  };

  double get _pricePerSeat => widget.dinner.pricePerSeat;
  double get _subtotal => _pricePerSeat * _seats;
  double get _discount => _promoApplied
      ? (_validPromos[_promoController.text.trim().toUpperCase()] ?? 0)
      : 0;

  /// Preview total. The server is authoritative: `POST /events/:id/bookings`
  /// recomputes `total = seats * pricePerSeat - discount` and rejects any
  /// unknown/inactive promo, so this is only a client-side estimate.
  double get _total => _subtotal - _discount;

  /// Method label sent with the booking.
  ///
  /// This screen offers exactly one method — pay at the venue — and collects no
  /// card data, so the label must name that method rather than a card the guest
  /// never presented. [Booking.kDefaultPaymentMethod] carries it.
  String get _paymentLabel => Booking.kDefaultPaymentMethod;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    if (user != null && user.name.isNotEmpty) {
      _nameController.text = user.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: const Text('Checkout', maxLines: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          _buildStepIndicator(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: switch (_currentStep) {
                0 => _buildSeatsStep(),
                1 => _buildGuestInfoStep(),
                _ => _buildReviewStep(),
              },
            ),
          ),
          // Bottom bar
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ── Step indicator ──
  Widget _buildStepIndicator() {
    const steps = ['Seats', 'Guest Info', 'Confirm'];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.paddingScreen,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isActive = i == _currentStep;
          final isDone = i < _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: isDone || isActive
                          ? AppColors.primary
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i < steps.length - 1) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Step 0: Select seats ──
  Widget _buildSeatsStep() {
    return SingleChildScrollView(
      key: const ValueKey('seats'),
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dinner summary
          _buildDinnerSummary(),
          const SizedBox(height: AppSpacing.lg),
          // Number of seats
          Text(
            'Number of seats',
            style: AppTextStyles.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.people_rounded,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                // Label takes the slack so the stepper controls stay reachable
                // on narrow screens and at large text scales.
                Expanded(
                  child: Text(
                    '$_seats seat${_seats > 1 ? 's' : ''}',
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: _seats > 1 ? () => setState(() => _seats--) : null,
                  color: AppColors.textSecondary,
                ),
                Text(
                  '$_seats',
                  style: AppTextStyles.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _seats < widget.dinner.availableSeats
                      ? () => setState(() => _seats++)
                      : null,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          if (widget.dinner.availableSeats <= 4) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Only ${widget.dinner.availableSeats} seats left!',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.danger),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          // Quick price preview
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Estimated total',
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Rs ${_total.toStringAsFixed(2)}',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Guest information ──
  Widget _buildGuestInfoStep() {
    return SingleChildScrollView(
      key: const ValueKey('guest'),
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Guest Information',
            style: AppTextStyles.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter the details for the primary guest.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildTextField(
            controller: _nameController,
            label: 'Full Name',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildTextField(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildTextField(
            controller: _phoneController,
            label: 'Phone Number',
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildTextField(
            controller: _notesController,
            label: 'Special Requests (optional)',
            icon: Icons.notes_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Promo code
          Text('Promo Code', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: _promoApplied
                    ? AppColors.success
                    : _promoError != null
                    ? AppColors.danger
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _promoApplied
                      ? Icons.check_circle_rounded
                      : Icons.local_offer_rounded,
                  color: _promoApplied
                      ? AppColors.success
                      : AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _promoController,
                    decoration: InputDecoration(
                      hintText: 'Enter promo code',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      helperText: _promoError,
                      helperStyle: AppTextStyles.caption.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                    style: AppTextStyles.bodyMedium,
                    enabled: !_promoApplied,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                if (_promoApplied)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _promoApplied = false;
                        _promoError = null;
                        _promoController.clear();
                      });
                    },
                    child: Text(
                      'Remove',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _applyPromo,
                    child: Text(
                      'Apply',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_promoApplied) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Rs ${_discount.toStringAsFixed(2)} discount applied!',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 2: Review + Payment ──
  Widget _buildReviewStep() {
    return SingleChildScrollView(
      key: const ValueKey('review'),
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Booking summary
          Text(
            'Booking Summary',
            style: AppTextStyles.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildDinnerSummary(),
          const SizedBox(height: AppSpacing.lg),

          // Guest details recap
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guest Details',
                  style: AppTextStyles.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                _RecapRow(
                  icon: Icons.person_rounded,
                  label: 'Name',
                  value: _nameController.text,
                ),
                const SizedBox(height: AppSpacing.xs),
                _RecapRow(
                  icon: Icons.email_rounded,
                  label: 'Email',
                  value: _emailController.text,
                ),
                const SizedBox(height: AppSpacing.xs),
                _RecapRow(
                  icon: Icons.phone_rounded,
                  label: 'Phone',
                  value: _phoneController.text,
                ),
                const SizedBox(height: AppSpacing.xs),
                _RecapRow(
                  icon: Icons.people_rounded,
                  label: 'Seats',
                  value: '$_seats',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Price breakdown
          Text(
            'Price Breakdown',
            style: AppTextStyles.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  label:
                      'Rs ${_pricePerSeat.toStringAsFixed(0)} x $_seats seat${_seats > 1 ? 's' : ''}',
                  value: 'Rs ${_subtotal.toStringAsFixed(2)}',
                ),
                if (_discount > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _SummaryRow(
                    label:
                        'Discount (${_promoController.text.trim().toUpperCase()})',
                    value: '-Rs ${_discount.toStringAsFixed(2)}',
                    valueColor: AppColors.success,
                  ),
                ],
                const Divider(height: AppSpacing.lg),
                _SummaryRow(
                  label: 'Total',
                  value: 'Rs ${_total.toStringAsFixed(2)}',
                  isBold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Payment method — pay at the venue (no card collected in-app).
          Text('Payment Method', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          _PaymentMethodTile(
            icon: Icons.payments_rounded,
            title: 'Pay at venue',
            subtitle: 'No card required — settle when you arrive',
            isSelected: true,
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  // ── Dinner summary card (reused) ──
  Widget _buildDinnerSummary() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Image.asset(
              widget.dinner.imagePath ?? 'assets/images/hero_tasting.png',
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.dinner.title,
                  style: AppTextStyles.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.dinner.restaurant.name,
                  style: AppTextStyles.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${widget.dinner.formattedDate} at ${widget.dinner.formattedTime}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar (contextual per step) ──
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: switch (_currentStep) {
          0 => PrimaryButton(
            text: 'Continue — Guest Info',
            onPressed: () => setState(() => _currentStep = 1),
          ),
          1 => PrimaryButton(
            text: 'Continue — Review',
            onPressed: () => setState(() => _currentStep = 2),
          ),
          _ => PrimaryButton(
            text: 'Confirm Booking',
            isLoading: _submitting,
            onPressed: _submit,
          ),
        },
      ),
    );
  }

  // ── Text field helper ──
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: label,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isDense: true,
              ),
              style: AppTextStyles.bodyMedium,
              keyboardType: keyboardType,
              maxLines: maxLines,
            ),
          ),
        ],
      ),
    );
  }

  // ── Apply promo code ──
  void _applyPromo() {
    final code = _promoController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _promoError = 'Enter a promo code');
      return;
    }
    if (_validPromos.containsKey(code)) {
      setState(() {
        _promoApplied = true;
        _promoError = null;
      });
    } else {
      setState(() => _promoError = 'Invalid promo code');
    }
  }

  // ── Submit booking ──
  Future<void> _submit() async {
    if (_submitting) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in to book.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final booking = await ref
          .read(bookingsControllerProvider)
          .join(
            dinner: widget.dinner,
            user: user,
            seats: _seats,
            promoCode: _promoApplied
                ? _promoController.text.trim().toUpperCase()
                : null,
            paymentLabel: _paymentLabel,
          );
      if (!mounted) return;

      // Phase 2a: Stripe removed. Booking is confirmed immediately.
      widget.onComplete?.call(booking);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}

// ── Helper widgets ──

class _RecapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RecapRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 16),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            '$label: ',
            style: AppTextStyles.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: AppTextStyles.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;

  const _PaymentMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.primary,
              size: 20,
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: isBold
                ? AppTextStyles.titleMedium
                : AppTextStyles.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style:
                (isBold ? AppTextStyles.titleMedium : AppTextStyles.bodyMedium)
                    .copyWith(
                      color:
                          valueColor ??
                          (isBold ? AppColors.primary : AppColors.textPrimary),
                    ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
