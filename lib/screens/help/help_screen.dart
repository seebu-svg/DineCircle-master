import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/safety.dart';
import '../../providers/safety_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/data_view.dart';
import '../bookings/bookings_screen.dart';
import '../safety/blocked_users_screen.dart';
import '../safety/my_reports_screen.dart';
import '../support/feedback_form_screen.dart';

/// Help & Feedback hub (P2 Safety & Trust).
///
/// Every control here performs a real navigation or reveals real data:
/// feedback goes through `POST /feedback`, ticket history through
/// `GET /users/me/feedback`, and the safety shortcuts land on the live
/// report/block screens. The former static mock of this screen (dead search,
/// dead contact buttons, dead legal tiles) is gone — nothing on this screen
/// is a no-op.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _scrollController = ScrollController();
  String _query = '';

  static const List<_Faq> _faqs = [
    _Faq(
      'How do I book a dinner?',
      'Browse events on the Home or Explore screen, tap a dinner you like, '
          'then tap "Join Dinner". Pick your seats, choose a payment method and '
          'confirm — your ticket appears under My Bookings.',
    ),
    _Faq(
      'How do I create a dining event?',
      'Tap the + button in the bottom navigation bar. Follow the steps to '
          'choose a restaurant, set the date and time, configure your menu, and '
          'publish your event.',
    ),
    _Faq(
      'How do earnings work?',
      'As a host you earn from each seat sold at your events. Revenue lands '
          'in your wallet after the event; platform fees are deducted '
          'automatically and you can withdraw to your bank account.',
    ),
    _Faq(
      'What is the cancellation policy?',
      'Cancellation policies vary by event — check the event details before '
          'booking. Generally full refunds are available up to 24 hours before '
          'the event starts.',
    ),
    _Faq(
      'How do I block or report someone?',
      'Open the person\u2019s profile (or a message, review or event) and use '
          'its menu to Report or Block. Blocking removes the follow relationship '
          'both ways and hides each other\u2019s profiles, content and events.',
    ),
    _Faq(
      'What happens after I submit a report?',
      'You get an RP reference immediately. Our team reviews the report and '
          'updates its status — pending, under review, resolved or dismissed. '
          'The reported account is never told who reported it.',
    ),
    _Faq(
      'Is a blocked person told I blocked them?',
      'No. They simply can no longer see, follow or message you, and you '
          'disappear from each other\u2019s discovery. You can undo a block any '
          'time under Settings → Privacy & Security → Blocked Users.',
    ),
  ];

  List<_Faq> get _visibleFaqs {
    if (_query.trim().isEmpty) return _faqs;
    final needle = _query.trim().toLowerCase();
    return _faqs
        .where(
          (faq) =>
              faq.question.toLowerCase().contains(needle) ||
              faq.answer.toLowerCase().contains(needle),
        )
        .toList();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToFaqs() {
    _scrollController.animateTo(
      _scrollController.offset + 260,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openForm(FeedbackCategory? category) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeedbackFormScreen(initialCategory: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedback = ref.watch(myFeedbackProvider);
    final faqs = _visibleFaqs;
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: const Text('Help & Feedback', maxLines: 1),
        ),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    key: const Key('helpSearchField'),
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search help articles\u2026',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Quick links', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _QuickLinkCard(
                  key: const Key('helpQuickLinkFaq'),
                  keyName: 'helpQuickLinkFaq',
                  icon: Icons.help_outline_rounded,
                  label: 'FAQs',
                  onTap: _scrollToFaqs,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _QuickLinkCard(
                  key: const Key('helpQuickLinkContact'),
                  keyName: 'helpQuickLinkContact',
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Contact Us',
                  onTap: () => _openForm(FeedbackCategory.general),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _QuickLinkCard(
                  key: const Key('helpQuickLinkReports'),
                  keyName: 'helpQuickLinkReports',
                  icon: Icons.shield_outlined,
                  label: 'My Reports',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyReportsScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Frequently Asked Questions',
            style: AppTextStyles.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (faqs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Text(
                'No articles match "$_query". Try different words, or send '
                'us a question through Contact Us.',
                style: AppTextStyles.bodySmall,
              ),
            )
          else
            for (final faq in faqs) _FaqTile(faq: faq),
          const SizedBox(height: AppSpacing.xl),
          Text('Support tickets', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          _SupportTile(
            keyName: 'helpSendFeedback',
            icon: Icons.send_rounded,
            title: 'Send feedback',
            subtitle: 'Bug, feature idea, booking or payment issue',
            onTap: () => _openForm(null),
          ),
          _SupportTile(
            keyName: 'helpBookingStatus',
            icon: Icons.confirmation_number_rounded,
            title: 'My bookings',
            subtitle: 'Check the status of your reservations',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const BookingsScreen())),
          ),
          _SupportTile(
            keyName: 'helpPaymentIssues',
            icon: Icons.payment_rounded,
            title: 'Payment issue?',
            subtitle: 'Tell us and we will trace the transaction',
            onTap: () => _openForm(FeedbackCategory.payment),
          ),
          _SupportTile(
            keyName: 'helpBlockedUsers',
            icon: Icons.block_rounded,
            title: 'Blocked users',
            subtitle: 'Review or undo your blocks',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Your tickets', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          DataView<List<FeedbackItem>>(
            value: feedback,
            onRetry: () => ref.invalidate(myFeedbackProvider),
            isEmpty: (items) => items.isEmpty,
            emptyMessage:
                'No tickets yet \u2014 anything you send us shows '
                'up here with its status.',
            builder: (context, items) => Column(
              children: [for (final item in items) _TicketTile(item: item)],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _Faq {
  const _Faq(this.question, this.answer);
  final String question;
  final String answer;
}

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({
    super.key,
    required this.keyName,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String keyName;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: AppTextStyles.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final _Faq faq;

  const _FaqTile({required this.faq});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // A Material host is required: ListTile paints its background and ink on
    // the nearest Material ancestor, and a decorated Container would both hide
    // those effects and trip a framework assertion.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Column(
          children: [
            ListTile(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ),
              title: Text(widget.faq.question, style: AppTextStyles.titleSmall),
              trailing: Icon(
                _isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AppColors.textSecondary,
              ),
            ),
            if (_isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Text(
                  widget.faq.answer,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.keyName,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String keyName;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        key: Key(keyName),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: const BorderSide(color: AppColors.border),
        ),
        tileColor: AppColors.surface,
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: AppTextStyles.titleSmall),
        subtitle: Text(subtitle, style: AppTextStyles.bodySmall),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.item});

  final FeedbackItem item;

  Color get _statusColor => switch (item.status) {
    FeedbackStatus.open => AppColors.warning,
    FeedbackStatus.inProgress => AppColors.info,
    FeedbackStatus.resolved => AppColors.success,
    FeedbackStatus.closed => AppColors.textTertiary,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('ticketTile_${item.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.paddingCard),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.subject, style: AppTextStyles.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${item.category.label} \u00b7 ${item.ticket}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Text(
              item.status.label,
              style: AppTextStyles.labelSmall.copyWith(color: _statusColor),
            ),
          ),
        ],
      ),
    );
  }
}
