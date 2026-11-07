import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/dinner.dart';
import '../../models/host_models.dart';
import '../../models/restaurant.dart';
import '../../models/user_profile.dart';
import '../../api/api_exception.dart';
import '../../providers/events_provider.dart';
import '../../providers/restaurants_provider.dart';
import '../../providers/users_provider.dart';
import '../../repositories/events_repository.dart';
import '../../screens/detail/dinner_detail_screen.dart';
import '../../widgets/buttons.dart';
import '../../data/mock_data.dart';

/// Create Dinner screen: 6-step wizard (spec section 10).
///
/// Steps: Experience Details → Restaurant & Venue → Date & Schedule
///        → Guests & Dining → Menu & Pricing → Review & Submit
class CreateDinnerScreen extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;
  const CreateDinnerScreen({super.key, this.onComplete});
  @override
  ConsumerState<CreateDinnerScreen> createState() => _CreateDinnerScreenState();
}

class _CreateDinnerScreenState extends ConsumerState<CreateDinnerScreen> {
  int _currentStep = 0;
  final int _totalSteps = 6;
  bool _isPublished = false;
  bool _bookingsPaused = false;
  bool _publishing = false;
  bool _termsAccepted = false;

  // Inline validation errors keyed by field name.
  final Map<String, String> _errors = {};

  // Step 1: Experience Details
  final _nameCtrl = TextEditingController(text: 'Omakase Experience');
  final _descCtrl = TextEditingController(
    text:
        'An intimate 8-course omakase experience featuring seasonal '
        'ingredients sourced from local markets.',
  );
  String _coverImage = 'assets/images/hero_tasting.png';
  String _category = 'Food Experience';

  // Step 2: Restaurant & Venue
  Restaurant? _selectedRestaurant;

  // Step 3: Date & Schedule
  DateTime _eventDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _startTime = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 0);
  int _totalSeats = 12;
  int _minAttendees = 4;
  int _maxAttendees = 12;
  bool _isPublic = true;

  // Step 4: Guests & Dining
  String _guestAccess = 'Open to Everyone';
  bool _approvalRequired = false;
  int _guestLimit = 2;
  String _cancellationPolicy = 'Free up to 48h';
  bool _waitlistEnabled = true;
  String _cuisine = 'Japanese';
  String _dressCode = 'Smart Casual';
  String _ageRestriction = 'None';
  final Set<String> _dietaryInfo = {'Gluten-Free'};
  final Set<String> _eventRules = {'Punctuality required'};
  bool _isSpecialMenu = true;

  // Step 5: Menu & Pricing
  bool _isPaid = true;
  double _pricePerPerson = 185.0;
  double _hostContribution = 50.0;
  final List<_MenuItemDraft> _menuItems = [
    _MenuItemDraft(
      name: 'Sashimi Platter',
      description: 'Fresh seasonal fish selection',
      price: 35,
    ),
    _MenuItemDraft(
      name: 'Wagyu Tataki',
      description: 'Seared A5 wagyu with ponzu',
      price: 45,
    ),
    _MenuItemDraft(
      name: 'Matcha Dessert',
      description: 'House-made matcha tiramisu',
      price: 18,
    ),
  ];

  static const _coverImages = [
    'assets/images/hero_tasting.png',
    'assets/images/dish_sushi.png',
    'assets/images/dish_steak.png',
    'assets/images/dish_pasta.png',
    'assets/images/dish_brunch.png',
    'assets/images/dish_dessert.png',
    'assets/images/dish_tacos.png',
    'assets/images/venue_interior.png',
    'assets/images/venue_rooftop.png',
    'assets/images/venue_bar.png',
  ];

  static const _stepNames = [
    'Experience Details',
    'Restaurant & Venue',
    'Date & Schedule',
    'Guests & Dining',
    'Menu & Pricing',
    'Review & Submit',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// Step-level validation before allowing forward navigation.
  bool _validateStep() {
    _errors.clear();
    switch (_currentStep) {
      case 0: // Experience Details
        if (_nameCtrl.text.trim().length < 3) {
          _errors['name'] = 'Name must be at least 3 characters';
        }
        if (_descCtrl.text.trim().isEmpty) {
          _errors['desc'] = 'Please add a short description';
        }
        break;
      case 1: // Restaurant & Venue
        if (_selectedRestaurant == null) {
          _errors['restaurant'] = 'Select a verified partner venue';
        }
        break;
      case 2: // Date & Schedule
        final start = _startTime.hour * 60 + _startTime.minute;
        var end = _endTime.hour * 60 + _endTime.minute;
        if (end <= start) end += 24 * 60;
        if (_eventDate.isBefore(
          DateTime.now().subtract(const Duration(days: 1)),
        )) {
          _errors['date'] = 'Event date must be in the future';
        }
        if ((end - start).clamp(30, 600) < 30) {
          _errors['time'] = 'Event must be at least 30 minutes';
        }
        if (_minAttendees > _maxAttendees) {
          _errors['attendees'] = 'Minimum attendees cannot exceed maximum';
        }
        if (_maxAttendees > _totalSeats) {
          _errors['capacity'] = 'Max attendees cannot exceed total seats';
        }
        break;
      case 4: // Menu & Pricing
        if (_isPaid && _pricePerPerson <= 0) {
          _errors['price'] = 'Set a price greater than zero';
        }
        break;
    }
    if (_errors.isNotEmpty) {
      setState(() {});
      return false;
    }
    return true;
  }

  void _nextStep() {
    if (!_validateStep()) return;
    if (_currentStep < _totalSteps - 1) setState(() => _currentStep++);
  }

  void _previousStep() {
    _errors.clear();
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  void _goToStep(int step) {
    _errors.clear();
    setState(() => _currentStep = step.clamp(0, _totalSteps - 1));
  }

  /// Warn before discarding the wizard.
  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Discard draft?'),
        content: const Text('Any unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Derived values ────────────────────────────────────────────────────────

  // DineCircle charges hosts no commission (the server carries
  // `PLATFORM_COMMISSION_RATE = 0`) and moves no money: guests pay the host at
  // the venue. Quoting a percentage here would advertise a cut the platform
  // never takes, so the fee is pinned to zero to match the server.
  double get _platformFee => 0;
  double get _estimatedPayout => _isPaid ? _pricePerPerson - _platformFee : 0;

  int get _durationMinutes {
    final start = _startTime.hour * 60 + _startTime.minute;
    var end = _endTime.hour * 60 + _endTime.minute;
    if (end <= start) end += 24 * 60;
    return (end - start).clamp(30, 600);
  }

  // ── Server interactions ───────────────────────────────────────────────────

  Future<void> _publish() async {
    if (_publishing) return;
    // Full validation before publish.
    for (var i = 0; i < _totalSteps - 1; i++) {
      _currentStep = i;
      if (!_validateStep()) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please fix errors on step ${i + 1}: ${_stepNames[i]}',
            ),
          ),
        );
        return;
      }
    }
    _currentStep = _totalSteps - 1;
    final restaurant = _selectedRestaurant;
    if (restaurant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a restaurant before publishing.')),
      );
      return;
    }
    final title = _nameCtrl.text.trim();
    if (title.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Give your dinner a name (at least 3 characters).'),
        ),
      );
      return;
    }
    final draft = _buildDraft();
    setState(() => _publishing = true);
    try {
      await ref.read(eventsControllerProvider).publish(draft);
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _isPublished = true;
      });
      widget.onComplete?.call();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not publish. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  NewDinnerDraft _buildDraft() {
    return NewDinnerDraft(
      title: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      restaurantId: _selectedRestaurant?.id ?? '',
      coverImage: _coverImage,
      startAt: DateTime(
        _eventDate.year,
        _eventDate.month,
        _eventDate.day,
        _startTime.hour,
        _startTime.minute,
      ),
      durationMinutes: _durationMinutes,
      seatsTotal: _totalSeats,
      pricePerSeat: _isPaid ? _pricePerPerson : 0,
      audience: _isPublic ? 'public' : 'friends',
      tags: [_cuisine],
      requiresApproval: _approvalRequired,
      menu: _menuItems
          .map((m) => MenuCourseDraft(name: m.name, description: m.description))
          .toList(),
    );
  }

  Future<void> _saveDraft() async {
    if (_publishing) return;
    final title = _nameCtrl.text.trim();
    if (title.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Give your dinner a name (at least 3 characters).'),
        ),
      );
      return;
    }
    final restaurant = _selectedRestaurant;
    if (restaurant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick a restaurant before saving a draft.'),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _publishing = true);
    try {
      await ref
          .read(eventsControllerProvider)
          .publish(_buildDraft(), asDraft: true);
      if (!mounted) return;
      setState(() => _publishing = false);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Draft saved')));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save draft. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _previewDraft() {
    final restaurant = _selectedRestaurant ?? MockData.restaurants.first;
    final me = ref.read(currentUserProvider);
    final startAt = DateTime(
      _eventDate.year,
      _eventDate.month,
      _eventDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final local = Dinner(
      id: 'preview',
      title: _nameCtrl.text.trim().isEmpty
          ? 'Untitled dinner'
          : _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      restaurant: restaurant,
      host: me ?? UserProfile(id: 'preview-host', name: 'You'),
      dateTime: startAt,
      totalSeats: _totalSeats,
      bookedSeats: 0,
      pricePerSeat: _isPaid ? _pricePerPerson : 0,
      imagePath: _coverImage,
      menu: [
        for (final (i, item) in _menuItems.indexed)
          MenuItem(
            id: 'preview-$i',
            name: item.name,
            description: item.description,
            price: item.price,
          ),
      ],
      tags: [_cuisine],
      isPublic: _isPublic,
      dressCode: _dressCode,
      ageRestriction: _ageRestriction == 'None' ? null : _ageRestriction,
      cancellationPolicy: _cancellationPolicy,
      endsAt: startAt.add(Duration(minutes: _durationMinutes)),
      hostStatus: HostEventStatus.draft,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DinnerDetailScreen(dinner: local)),
    );
  }

  String _formatDate(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '${h.toString()}:${t.minute.toString().padLeft(2, '0')} $p';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final exit = await _confirmExit();
        if (!context.mounted) return;
        if (exit) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: const Text('Create Dinner', maxLines: 1),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              if (!await _confirmExit()) return;
              if (!context.mounted) return;
              Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.save_rounded),
              tooltip: 'Save draft',
              onPressed: _publishing ? null : _saveDraft,
            ),
          ],
        ),
        body: Column(
          children: [
            // Step name header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.paddingScreen,
                AppSpacing.sm,
                AppSpacing.paddingScreen,
                0,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Step ${_currentStep + 1} of $_totalSteps',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          _stepNames[_currentStep],
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _TappableProgressBar(
                    currentStep: _currentStep,
                    totalSteps: _totalSteps,
                    onTap: (step) {
                      if (step <= _currentStep) _goToStep(step);
                    },
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildStepContent(),
              ),
            ),
            // Bottom bar
            if (!_isPublished)
              Container(
                padding: const EdgeInsets.all(AppSpacing.paddingScreen),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      if (_currentStep > 0)
                        SecondaryButton(text: 'Back', onPressed: _previousStep),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: PrimaryButton(
                          text: _currentStep == _totalSteps - 1
                              ? 'Publish'
                              : 'Next',
                          isLoading:
                              _currentStep == _totalSteps - 1 && _publishing,
                          onPressed: _currentStep == _totalSteps - 1
                              ? _publish
                              : _nextStep,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(AppSpacing.paddingScreen),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PrimaryButton(
                        text: 'Edit Event',
                        icon: Icons.edit_rounded,
                        onPressed: () => setState(() {
                          _isPublished = false;
                          _currentStep = 0;
                        }),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: SecondaryButton(
                              text: _bookingsPaused ? 'Resume' : 'Pause',
                              icon: _bookingsPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              onPressed: () {
                                setState(
                                  () => _bookingsPaused = !_bookingsPaused,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _bookingsPaused
                                          ? 'Bookings paused'
                                          : 'Bookings resumed',
                                    ),
                                    backgroundColor: AppColors.info,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: SecondaryButton(
                              text: 'Cancel Event',
                              icon: Icons.cancel_rounded,
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Event cancelled. Refunds processing.',
                                    ),
                                    backgroundColor: AppColors.danger,
                                  ),
                                );
                                Navigator.pop(context);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _Step1ExperienceDetails(
          key: const ValueKey('s1'),
          nameCtrl: _nameCtrl,
          descCtrl: _descCtrl,
          category: _category,
          onCategoryChanged: (v) => setState(() => _category = v),
          coverImage: _coverImage,
          onCoverChanged: (v) => setState(() => _coverImage = v),
          error: _errors,
        );
      case 1:
        return _Step2Restaurant(
          key: const ValueKey('s2'),
          selectedRestaurant: _selectedRestaurant,
          onRestaurantSelected: (r) {
            setState(() {
              _selectedRestaurant = r;
              _errors.remove('restaurant');
            });
          },
          error: _errors['restaurant'],
        );
      case 2:
        return _Step3DateSchedule(
          key: const ValueKey('s3'),
          eventDate: _eventDate,
          onDateChanged: (d) => setState(() => _eventDate = d),
          startTime: _startTime,
          onStartTimeChanged: (t) => setState(() => _startTime = t),
          endTime: _endTime,
          onEndTimeChanged: (t) => setState(() => _endTime = t),
          totalSeats: _totalSeats,
          onTotalSeatsChanged: (v) => setState(() => _totalSeats = v),
          minAttendees: _minAttendees,
          onMinAttendeesChanged: (v) => setState(() => _minAttendees = v),
          maxAttendees: _maxAttendees,
          onMaxAttendeesChanged: (v) => setState(() => _maxAttendees = v),
          isPublic: _isPublic,
          onPublicChanged: (v) => setState(() => _isPublic = v),
          formatDate: _formatDate,
          formatTime: _formatTime,
          errors: _errors,
        );
      case 3:
        return _Step4GuestsDining(
          key: const ValueKey('s4'),
          guestAccess: _guestAccess,
          onGuestAccessChanged: (v) => setState(() => _guestAccess = v),
          approvalRequired: _approvalRequired,
          onApprovalChanged: (v) => setState(() => _approvalRequired = v),
          guestLimit: _guestLimit,
          onGuestLimitChanged: (v) => setState(() => _guestLimit = v),
          cancellationPolicy: _cancellationPolicy,
          onPolicyChanged: (v) => setState(() => _cancellationPolicy = v),
          waitlistEnabled: _waitlistEnabled,
          onWaitlistChanged: (v) => setState(() => _waitlistEnabled = v),
          cuisine: _cuisine,
          onCuisineChanged: (v) => setState(() => _cuisine = v),
          dressCode: _dressCode,
          onDressCodeChanged: (v) => setState(() => _dressCode = v),
          ageRestriction: _ageRestriction,
          onAgeRestrictionChanged: (v) => setState(() => _ageRestriction = v),
          dietaryInfo: _dietaryInfo,
          onDietaryToggled: (v) => setState(() {
            if (_dietaryInfo.contains(v)) {
              _dietaryInfo.remove(v);
            } else {
              _dietaryInfo.add(v);
            }
          }),
          eventRules: _eventRules,
          onRuleToggled: (v) => setState(() {
            if (_eventRules.contains(v)) {
              _eventRules.remove(v);
            } else {
              _eventRules.add(v);
            }
          }),
          isSpecialMenu: _isSpecialMenu,
          onSpecialMenuChanged: (v) => setState(() => _isSpecialMenu = v),
        );
      case 4:
        return _Step5MenuPricing(
          key: const ValueKey('s5'),
          isPaid: _isPaid,
          onPaidChanged: (v) => setState(() => _isPaid = v),
          pricePerPerson: _pricePerPerson,
          onPriceChanged: (v) => setState(() => _pricePerPerson = v),
          hostContribution: _hostContribution,
          onHostContributionChanged: (v) =>
              setState(() => _hostContribution = v),
          platformFee: _platformFee,
          estimatedPayout: _estimatedPayout,
          items: _menuItems,
          onAdd: (item) => setState(() => _menuItems.add(item)),
          onDelete: (i) => setState(() => _menuItems.removeAt(i)),
          error: _errors['price'],
        );
      case 5:
        return _Step6Review(
          key: const ValueKey('s6'),
          name: _nameCtrl.text,
          description: _descCtrl.text,
          coverImage: _coverImage,
          restaurant: _selectedRestaurant,
          category: _category,
          eventDate: _formatDate(_eventDate),
          startTime: _formatTime(_startTime),
          endTime: _formatTime(_endTime),
          totalSeats: _totalSeats,
          minAttendees: _minAttendees,
          maxAttendees: _maxAttendees,
          isPublic: _isPublic,
          isPaid: _isPaid,
          pricePerPerson: _pricePerPerson,
          hostContribution: _hostContribution,
          platformFee: _platformFee,
          estimatedPayout: _estimatedPayout,
          cuisine: _cuisine,
          dressCode: _dressCode,
          ageRestriction: _ageRestriction,
          dietaryInfo: _dietaryInfo,
          eventRules: _eventRules,
          isSpecialMenu: _isSpecialMenu,
          menuItems: _menuItems,
          guestAccess: _guestAccess,
          approvalRequired: _approvalRequired,
          guestLimit: _guestLimit,
          cancellationPolicy: _cancellationPolicy,
          waitlistEnabled: _waitlistEnabled,
          termsAccepted: _termsAccepted,
          onTermsChanged: (v) => setState(() => _termsAccepted = v),
          onSaveDraft: _saveDraft,
          onPreview: _previewDraft,
          onEditStep: _goToStep,
        );
      default:
        return const SizedBox();
    }
  }
}

// =============================================================================
// Menu item draft
// =============================================================================

class _MenuItemDraft {
  String name;
  String description;
  double price;
  _MenuItemDraft({
    required this.name,
    required this.description,
    required this.price,
  });
}

// =============================================================================
// Tappable progress bar, shows step dots with labels, allows backward taps
// =============================================================================

class _TappableProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final ValueChanged<int> onTap;

  const _TappableProgressBar({
    required this.currentStep,
    required this.totalSteps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (i) {
        final done = i <= currentStep;
        return Expanded(
          child: GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 4,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: done ? AppColors.primary : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// =============================================================================
// Step 1: Experience Details
// =============================================================================

class _Step1ExperienceDetails extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final String coverImage;
  final ValueChanged<String> onCoverChanged;
  final Map<String, String> error;

  const _Step1ExperienceDetails({
    super.key,
    required this.nameCtrl,
    required this.descCtrl,
    required this.category,
    required this.onCategoryChanged,
    required this.coverImage,
    required this.onCoverChanged,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Experience Details', style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tell guests what makes this dinner special',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),

          _SectionLabel('Event Name *'),
          TextField(
            controller: nameCtrl,
            style: AppTextStyles.bodyMedium,
            decoration: _inputDecoration(
              'e.g. Omakase Experience',
              errorText: error['name'],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('Description *'),
          TextField(
            controller: descCtrl,
            maxLines: 4,
            style: AppTextStyles.bodySmall,
            decoration: _inputDecoration(
              'Describe your event...',
              errorText: error['desc'],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('Experience Category'),
          _ChipRow(
            options: MockData.eventCategoryOptions,
            selected: category,
            onSelected: onCategoryChanged,
          ),
          const SizedBox(height: AppSpacing.lg),

          _SectionLabel('Cover Image'),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _CreateDinnerScreenState._coverImages.length,
              itemBuilder: (ctx, i) {
                final path = _CreateDinnerScreenState._coverImages[i];
                final isSelected = path == coverImage;
                return GestureDetector(
                  onTap: () => onCoverChanged(path),
                  child: Container(
                    margin: const EdgeInsets.only(right: AppSpacing.sm),
                    width: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      child: Image.asset(path, fit: BoxFit.cover),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 2: Restaurant & Venue
// =============================================================================

class _Step2Restaurant extends ConsumerWidget {
  final Restaurant? selectedRestaurant;
  final ValueChanged<Restaurant> onRestaurantSelected;
  final String? error;

  const _Step2Restaurant({
    super.key,
    required this.selectedRestaurant,
    required this.onRestaurantSelected,
    this.error,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantsAsync = ref.watch(restaurantsListProvider(null));
    final restaurants = restaurantsAsync.valueOrNull ?? const <Restaurant>[];
    final publishable = restaurants
        .where((r) => r.isPartner && r.partnershipStatus == 'verified')
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Restaurant & Venue', style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Select a verified partner venue for your event',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),

          if (error != null) _InlineError(error!),
          if (error != null) const SizedBox(height: AppSpacing.sm),

          if (restaurantsAsync.isLoading && restaurants.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: LinearProgressIndicator(),
            )
          else if (publishable.isEmpty)
            _EmptyVenueState(hasRestaurants: restaurants.isNotEmpty)
          else
            ...publishable.map(
              (r) => _VenueTile(
                restaurant: r,
                isSelected: selectedRestaurant?.id == r.id,
                onTap: () => onRestaurantSelected(r),
              ),
            ),

          const SizedBox(height: AppSpacing.lg),
          if (selectedRestaurant != null) ...[
            _SectionLabel('Venue Details'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          selectedRestaurant!.name,
                          style: AppTextStyles.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${selectedRestaurant!.address}, ${selectedRestaurant!.city}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (selectedRestaurant!.cuisine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Cuisine: ${selectedRestaurant!.cuisine}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _EmptyVenueState extends StatelessWidget {
  final bool hasRestaurants;
  const _EmptyVenueState({required this.hasRestaurants});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        children: [
          Icon(
            Icons.storefront_rounded,
            color: AppColors.textTertiary,
            size: 40,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            hasRestaurants
                ? 'No verified venues yet in this area.'
                : 'No venues available yet.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'You can publish at verified partner venues. Contact a venue team to get on their calendar.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _VenueTile extends StatelessWidget {
  final Restaurant restaurant;
  final bool isSelected;
  final VoidCallback onTap;
  const _VenueTile({
    required this.restaurant,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Image.asset(
                restaurant.imagePath ?? 'assets/images/venue_interior.png',
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          restaurant.name,
                          style: AppTextStyles.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                        child: Text(
                          'Verified',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: Colors.black,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${restaurant.cuisine} · ${restaurant.address}',
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Step 3: Date & Schedule
// =============================================================================

class _Step3DateSchedule extends StatelessWidget {
  final DateTime eventDate;
  final ValueChanged<DateTime> onDateChanged;
  final TimeOfDay startTime;
  final ValueChanged<TimeOfDay> onStartTimeChanged;
  final TimeOfDay endTime;
  final ValueChanged<TimeOfDay> onEndTimeChanged;
  final int totalSeats;
  final ValueChanged<int> onTotalSeatsChanged;
  final int minAttendees;
  final ValueChanged<int> onMinAttendeesChanged;
  final int maxAttendees;
  final ValueChanged<int> onMaxAttendeesChanged;
  final bool isPublic;
  final ValueChanged<bool> onPublicChanged;
  final String Function(DateTime) formatDate;
  final String Function(TimeOfDay) formatTime;
  final Map<String, String> errors;

  const _Step3DateSchedule({
    super.key,
    required this.eventDate,
    required this.onDateChanged,
    required this.startTime,
    required this.onStartTimeChanged,
    required this.endTime,
    required this.onEndTimeChanged,
    required this.totalSeats,
    required this.onTotalSeatsChanged,
    required this.minAttendees,
    required this.onMinAttendeesChanged,
    required this.maxAttendees,
    required this.onMaxAttendeesChanged,
    required this.isPublic,
    required this.onPublicChanged,
    required this.formatDate,
    required this.formatTime,
    required this.errors,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Date & Schedule', style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'When and where will your event take place?',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),

          if (errors['date'] != null) _InlineError(errors['date']!),
          if (errors['time'] != null) _InlineError(errors['time']!),

          _SectionLabel('Event Date'),
          _PickerRow(
            icon: Icons.calendar_today_rounded,
            label: formatDate(eventDate),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: eventDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) onDateChanged(picked);
            },
          ),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('Start Time'),
          _PickerRow(
            icon: Icons.play_arrow_rounded,
            label: formatTime(startTime),
            onTap: () async {
              final p = await showTimePicker(
                context: context,
                initialTime: startTime,
              );
              if (p != null) onStartTimeChanged(p);
            },
          ),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('End Time'),
          _PickerRow(
            icon: Icons.stop_rounded,
            label: formatTime(endTime),
            onTap: () async {
              final p = await showTimePicker(
                context: context,
                initialTime: endTime,
              );
              if (p != null) onEndTimeChanged(p);
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          _SectionLabel('Capacity'),
          _StepperRow(
            label: 'Total Seats',
            value: totalSeats,
            min: 1,
            max: 30,
            onChanged: onTotalSeatsChanged,
          ),
          _StepperRow(
            label: 'Min Attendees',
            value: minAttendees,
            min: 1,
            max: totalSeats,
            onChanged: onMinAttendeesChanged,
          ),
          _StepperRow(
            label: 'Max Attendees',
            value: maxAttendees,
            min: minAttendees,
            max: 30,
            onChanged: onMaxAttendeesChanged,
          ),
          if (errors['attendees'] != null) _InlineError(errors['attendees']!),
          if (errors['capacity'] != null) _InlineError(errors['capacity']!),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('Event Visibility'),
          Row(
            children: [
              Expanded(
                child: _SegmentButton(
                  label: 'Public',
                  icon: Icons.public_rounded,
                  isSelected: isPublic,
                  onTap: () => onPublicChanged(true),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SegmentButton(
                  label: 'Private',
                  icon: Icons.lock_rounded,
                  isSelected: !isPublic,
                  onTap: () => onPublicChanged(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError(this.message);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 14,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 4: Guests & Dining
// =============================================================================

class _Step4GuestsDining extends StatelessWidget {
  final String guestAccess;
  final ValueChanged<String> onGuestAccessChanged;
  final bool approvalRequired;
  final ValueChanged<bool> onApprovalChanged;
  final int guestLimit;
  final ValueChanged<int> onGuestLimitChanged;
  final String cancellationPolicy;
  final ValueChanged<String> onPolicyChanged;
  final bool waitlistEnabled;
  final ValueChanged<bool> onWaitlistChanged;
  final String cuisine;
  final ValueChanged<String> onCuisineChanged;
  final String dressCode;
  final ValueChanged<String> onDressCodeChanged;
  final String ageRestriction;
  final ValueChanged<String> onAgeRestrictionChanged;
  final Set<String> dietaryInfo;
  final ValueChanged<String> onDietaryToggled;
  final Set<String> eventRules;
  final ValueChanged<String> onRuleToggled;
  final bool isSpecialMenu;
  final ValueChanged<bool> onSpecialMenuChanged;

  const _Step4GuestsDining({
    super.key,
    required this.guestAccess,
    required this.onGuestAccessChanged,
    required this.approvalRequired,
    required this.onApprovalChanged,
    required this.guestLimit,
    required this.onGuestLimitChanged,
    required this.cancellationPolicy,
    required this.onPolicyChanged,
    required this.waitlistEnabled,
    required this.onWaitlistChanged,
    required this.cuisine,
    required this.onCuisineChanged,
    required this.dressCode,
    required this.onDressCodeChanged,
    required this.ageRestriction,
    required this.onAgeRestrictionChanged,
    required this.dietaryInfo,
    required this.onDietaryToggled,
    required this.eventRules,
    required this.onRuleToggled,
    required this.isSpecialMenu,
    required this.onSpecialMenuChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Guests & Dining', style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Control who can attend and customize the experience',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),

          _SectionLabel('Guest Access'),
          Row(
            children: [
              Expanded(
                child: _SegmentButton(
                  label: 'Everyone',
                  icon: Icons.public_rounded,
                  isSelected: guestAccess == 'Open to Everyone',
                  onTap: () => onGuestAccessChanged('Open to Everyone'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _SegmentButton(
                  label: 'Followers',
                  icon: Icons.people_rounded,
                  isSelected: guestAccess == 'Followers Only',
                  onTap: () => onGuestAccessChanged('Followers Only'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _SegmentButton(
                  label: 'Invite',
                  icon: Icons.mail_rounded,
                  isSelected: guestAccess == 'Invite Only',
                  onTap: () => onGuestAccessChanged('Invite Only'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          _SectionLabel('Approval'),
          SwitchListTile(
            title: Text('Approval Required', style: AppTextStyles.bodyMedium),
            subtitle: Text(
              'Guests must be approved before attending',
              style: AppTextStyles.caption,
            ),
            value: approvalRequired,
            onChanged: onApprovalChanged,
            activeThumbColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
          ),
          if (approvalRequired) ...[
            const SizedBox(height: AppSpacing.sm),
            _StepperRow(
              label: 'Guest Limit per Booking',
              value: guestLimit,
              min: 1,
              max: 10,
              onChanged: onGuestLimitChanged,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          _SectionLabel('Cancellation Policy'),
          _ChipRow(
            options: MockData.cancellationPolicyOptions,
            selected: cancellationPolicy,
            onSelected: onPolicyChanged,
          ),
          const SizedBox(height: AppSpacing.lg),

          _SectionLabel('Waitlist'),
          SwitchListTile(
            title: Text('Enable Waitlist', style: AppTextStyles.bodyMedium),
            subtitle: Text(
              'Allow guests to join waitlist when full',
              style: AppTextStyles.caption,
            ),
            value: waitlistEnabled,
            onChanged: onWaitlistChanged,
            activeThumbColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.xl),

          const Divider(),
          const SizedBox(height: AppSpacing.lg),

          _SectionLabel('Cuisine'),
          _ChipRow(
            options: MockData.cuisineCategories
                .where((c) => c != 'All')
                .toList(),
            selected: cuisine,
            onSelected: onCuisineChanged,
          ),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('Dress Code'),
          _ChipRow(
            options: MockData.dressCodeOptions,
            selected: dressCode,
            onSelected: onDressCodeChanged,
          ),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('Age Requirements'),
          _ChipRow(
            options: MockData.ageRestrictionOptions,
            selected: ageRestriction,
            onSelected: onAgeRestrictionChanged,
          ),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('Dietary Information'),
          _MultiChipRow(
            options: MockData.dietaryOptions,
            selected: dietaryInfo,
            onToggled: onDietaryToggled,
          ),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('Event Rules'),
          _MultiChipRow(
            options: MockData.eventRuleOptions,
            selected: eventRules,
            onToggled: onRuleToggled,
          ),
          const SizedBox(height: AppSpacing.md),

          _SectionLabel('Special Menu'),
          SwitchListTile(
            title: Text(
              'Curated multi-course menu',
              style: AppTextStyles.bodyMedium,
            ),
            subtitle: Text(
              'Chef selection with paired courses',
              style: AppTextStyles.caption,
            ),
            value: isSpecialMenu,
            onChanged: onSpecialMenuChanged,
            activeThumbColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 5: Menu & Pricing
// =============================================================================

class _Step5MenuPricing extends StatelessWidget {
  final bool isPaid;
  final ValueChanged<bool> onPaidChanged;
  final double pricePerPerson;
  final ValueChanged<double> onPriceChanged;
  final double hostContribution;
  final ValueChanged<double> onHostContributionChanged;
  final double platformFee;
  final double estimatedPayout;
  final List<_MenuItemDraft> items;
  final ValueChanged<_MenuItemDraft> onAdd;
  final ValueChanged<int> onDelete;
  final String? error;

  const _Step5MenuPricing({
    super.key,
    required this.isPaid,
    required this.onPaidChanged,
    required this.pricePerPerson,
    required this.onPriceChanged,
    required this.hostContribution,
    required this.onHostContributionChanged,
    required this.platformFee,
    required this.estimatedPayout,
    required this.items,
    required this.onAdd,
    required this.onDelete,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Menu & Pricing', style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Set your menu and pricing model',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Menu items ──────────────────────────────────────────────────────
          _SectionLabel('Menu Items'),
          SecondaryButton(
            text: 'Add Menu Item',
            icon: Icons.add_rounded,
            isFullWidth: true,
            onPressed: () => _showAddItemSheet(context),
          ),
          const SizedBox(height: AppSpacing.md),
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.drag_handle_rounded,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: AppTextStyles.titleSmall),
                        const SizedBox(height: 2),
                        Text(item.description, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  Text(
                    'Rs ${item.price.toStringAsFixed(0)}',
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                      size: 20,
                    ),
                    onPressed: () => onDelete(i),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppSpacing.xl),

          const Divider(),
          const SizedBox(height: AppSpacing.lg),

          // ── Pricing ─────────────────────────────────────────────────────────
          _SectionLabel('Pricing Type'),
          Row(
            children: [
              Expanded(
                child: _SegmentButton(
                  label: 'Free',
                  icon: Icons.card_giftcard_rounded,
                  isSelected: !isPaid,
                  onTap: () => onPaidChanged(false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SegmentButton(
                  label: 'Paid',
                  icon: Icons.payments_rounded,
                  isSelected: isPaid,
                  onTap: () => onPaidChanged(true),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          if (!isPaid)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'This is a free event. No charges apply.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (error != null) _InlineError(error!),
            _SectionLabel('Price per Person'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Text(
                    'Rs',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextField(
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: AppTextStyles.titleMedium,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (v) => onPriceChanged(double.tryParse(v) ?? 0),
                      controller: TextEditingController(
                        text: pricePerPerson.toStringAsFixed(0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            _SectionLabel('Host Contribution'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Text(
                    'Rs',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.gold,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextField(
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: AppTextStyles.titleMedium,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          onHostContributionChanged(double.tryParse(v) ?? 0),
                      controller: TextEditingController(
                        text: hostContribution.toStringAsFixed(0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Column(
                children: [
                  _FeeRow(
                    label: 'Price per Person',
                    value: 'Rs ${pricePerPerson.toStringAsFixed(2)}',
                  ),
                  const Divider(height: 20),
                  _FeeRow(
                    label: 'Platform Fee (0%)',
                    value: 'Rs ${platformFee.toStringAsFixed(2)}',
                    valueColor: AppColors.danger,
                  ),
                  const Divider(height: 20),
                  _FeeRow(
                    label: 'Host Receives (per guest)',
                    value: 'Rs ${estimatedPayout.toStringAsFixed(2)}',
                    isBold: true,
                    valueColor: AppColors.success,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  void _showAddItemSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Menu Item', style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: nameCtrl,
                decoration: _inputDecoration('Item name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: descCtrl,
                decoration: _inputDecoration('Description'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _inputDecoration('Price'),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  text: 'Add Item',
                  onPressed: () {
                    if (nameCtrl.text.isNotEmpty) {
                      onAdd(
                        _MenuItemDraft(
                          name: nameCtrl.text,
                          description: descCtrl.text,
                          price: double.tryParse(priceCtrl.text) ?? 0,
                        ),
                      );
                      Navigator.pop(ctx);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Step 6: Review & Submit
// =============================================================================

class _Step6Review extends StatelessWidget {
  final String name;
  final String description;
  final String coverImage;
  final Restaurant? restaurant;
  final String category;
  final String eventDate;
  final String startTime;
  final String endTime;
  final int totalSeats;
  final int minAttendees;
  final int maxAttendees;
  final bool isPublic;
  final bool isPaid;
  final double pricePerPerson;
  final double hostContribution;
  final double platformFee;
  final double estimatedPayout;
  final String cuisine;
  final String dressCode;
  final String ageRestriction;
  final Set<String> dietaryInfo;
  final Set<String> eventRules;
  final bool isSpecialMenu;
  final List<_MenuItemDraft> menuItems;
  final String guestAccess;
  final bool approvalRequired;
  final int guestLimit;
  final String cancellationPolicy;
  final bool waitlistEnabled;
  final bool termsAccepted;
  final ValueChanged<bool> onTermsChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onPreview;
  final ValueChanged<int> onEditStep;

  const _Step6Review({
    super.key,
    required this.name,
    required this.description,
    required this.coverImage,
    required this.restaurant,
    required this.category,
    required this.eventDate,
    required this.startTime,
    required this.endTime,
    required this.totalSeats,
    required this.minAttendees,
    required this.maxAttendees,
    required this.isPublic,
    required this.isPaid,
    required this.pricePerPerson,
    required this.hostContribution,
    required this.platformFee,
    required this.estimatedPayout,
    required this.cuisine,
    required this.dressCode,
    required this.ageRestriction,
    required this.dietaryInfo,
    required this.eventRules,
    required this.isSpecialMenu,
    required this.menuItems,
    required this.guestAccess,
    required this.approvalRequired,
    required this.guestLimit,
    required this.cancellationPolicy,
    required this.waitlistEnabled,
    required this.termsAccepted,
    required this.onTermsChanged,
    required this.onSaveDraft,
    required this.onPreview,
    required this.onEditStep,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review & Submit', style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Review your event before publishing',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),

          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Image.asset(
              coverImage,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(name, style: AppTextStyles.headlineSmall),
          if (description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
              style: AppTextStyles.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          _ReviewSection(
            title: 'Experience',
            onEdit: () => onEditStep(0),
            children: [
              _ReviewRow(label: 'Category', value: category),
              _ReviewRow(
                label: 'Restaurant',
                value: restaurant?.name ?? 'Not selected',
              ),
              if (restaurant != null)
                _ReviewRow(
                  label: 'Venue',
                  value: '${restaurant!.address}, ${restaurant!.city}',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _ReviewSection(
            title: 'Date & Schedule',
            onEdit: () => onEditStep(2),
            children: [
              _ReviewRow(label: 'Date', value: eventDate),
              _ReviewRow(label: 'Time', value: '$startTime – $endTime'),
              _ReviewRow(
                label: 'Seats',
                value: '$totalSeats (min: $minAttendees, max: $maxAttendees)',
              ),
              _ReviewRow(
                label: 'Visibility',
                value: isPublic ? 'Public' : 'Private',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _ReviewSection(
            title: 'Guests & Dining',
            onEdit: () => onEditStep(3),
            children: [
              _ReviewRow(label: 'Access', value: guestAccess),
              _ReviewRow(
                label: 'Approval',
                value: approvalRequired
                    ? 'Required (limit: $guestLimit)'
                    : 'Not required',
              ),
              _ReviewRow(label: 'Cancellation', value: cancellationPolicy),
              _ReviewRow(
                label: 'Waitlist',
                value: waitlistEnabled ? 'Enabled' : 'Disabled',
              ),
              _ReviewRow(label: 'Cuisine', value: cuisine),
              _ReviewRow(label: 'Dress Code', value: dressCode),
              if (dietaryInfo.isNotEmpty)
                _ReviewRow(label: 'Dietary', value: dietaryInfo.join(', ')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _ReviewSection(
            title: 'Menu & Pricing',
            onEdit: () => onEditStep(4),
            children: [
              _ReviewRow(label: 'Type', value: isPaid ? 'Paid' : 'Free'),
              if (isPaid) ...[
                _ReviewRow(
                  label: 'Price/Person',
                  value: 'Rs ${pricePerPerson.toStringAsFixed(2)}',
                ),
                _ReviewRow(
                  label: 'Platform Fee (0%)',
                  value: 'Rs ${platformFee.toStringAsFixed(2)}',
                ),
                _ReviewRow(
                  label: 'Host Receives',
                  value: 'Rs ${estimatedPayout.toStringAsFixed(2)}',
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              _ReviewRow(label: 'Menu', value: '${menuItems.length} items'),
              ...menuItems.map(
                (m) => _ReviewRow(
                  label: '  · ${m.name}',
                  value: 'Rs ${m.price.toStringAsFixed(0)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Terms acknowledgment
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: termsAccepted,
                  onChanged: (v) => onTermsChanged(v ?? false),
                  activeColor: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'I confirm this event listing is accurate and I agree to the host terms and cancellation policy.',
                    style: AppTextStyles.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Actions
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  text: 'Save Draft',
                  icon: Icons.save_outlined,
                  onPressed: onSaveDraft,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  text: 'Preview',
                  icon: Icons.visibility_outlined,
                  onPressed: onPreview,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// =============================================================================
// Shared helpers
// =============================================================================

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: AppTextStyles.labelMedium),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
            const Icon(Icons.edit_rounded, color: AppColors.primary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
            onPressed: value > min ? () => onChanged(value - 1) : null,
            color: AppColors.primary,
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              style: AppTextStyles.titleSmall,
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
            onPressed: value < max ? () => onChanged(value + 1) : null,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: options.map((o) {
        final isSel = o == selected;
        return ChoiceChip(
          label: Text(
            o,
            style: AppTextStyles.labelSmall.copyWith(
              color: isSel ? Colors.white : AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          selected: isSel,
          onSelected: (_) => onSelected(o),
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surfaceElevated,
          side: BorderSide(color: isSel ? AppColors.primary : AppColors.border),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }
}

class _MultiChipRow extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggled;
  const _MultiChipRow({
    required this.options,
    required this.selected,
    required this.onToggled,
  });
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: options.map((o) {
        final isSel = selected.contains(o);
        return FilterChip(
          label: Text(
            o,
            style: AppTextStyles.labelSmall.copyWith(
              color: isSel ? Colors.white : AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          selected: isSel,
          onSelected: (_) => onToggled(o),
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surfaceElevated,
          side: BorderSide(color: isSel ? AppColors.primary : AppColors.border),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;
  const _FeeRow({
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
        Text(label, style: AppTextStyles.bodySmall),
        Text(
          value,
          style: AppTextStyles.titleSmall.copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback? onEdit;
  const _ReviewSection({
    required this.title,
    required this.children,
    this.onEdit,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child: Text(
                    'Edit',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: AppTextStyles.bodySmall)),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: AppTextStyles.labelSmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint, {String? errorText}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
    errorText: errorText,
    filled: true,
    fillColor: AppColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: BorderSide(
        color: errorText != null ? AppColors.danger : AppColors.border,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
  );
}
