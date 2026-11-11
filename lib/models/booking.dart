import '../utils/money.dart';
import '../utils/venue_time.dart';
import 'dinner.dart';
import 'user_profile.dart';

/// Booking status
enum BookingStatus {
  pending,
  confirmed,
  cancelled,
  completed,
  noShow,
  refunded,
}

/// Check-in status for digital event pass
enum CheckInStatus { notCheckedIn, checkedIn, expired }

/// Normalised payment lifecycle for a booking.
///
/// Derived from the server's [Booking.paymentStatus] first, that is the
/// authoritative gateway signal, and only falls back to the booking
/// [Booking.status] for legacy rows written before deferred payments existed.
/// Every money total in the app is computed from this one mapping so the
/// Payments surfaces can never disagree with each other.
enum BookingPaymentState { paid, pending, failed, refunded, notCharged }

/// Booking model
class Booking {
  /// Fallback method label for a booking created without an explicit method.
  ///
  /// DineCircle collects no payment in-app, the guest pays the venue directly
  ///, so the only honest default names that arrangement rather than a card
  /// brand no one entered. A real method from the server still wins.
  static const String kDefaultPaymentMethod = 'Pay at venue';

  final String id;
  final Dinner dinner;
  final UserProfile user;
  final int seats;
  final double subtotal;
  final double serviceFee;
  final double discount;
  final double totalAmount;
  final BookingStatus status;
  final DateTime createdAt;
  final String? qrCode;
  final String? promoCode;
  final String? guestName;
  final String? guestEmail;
  final String? guestPhone;
  final String paymentMethod;

  /// Server-side payment state for the Stripe deferred flow: '', 'paid',
  /// 'pending_payment', 'authorized', 'refunded' or 'failed'.
  final String paymentStatus;

  /// PaymentSheet client secret for a `pending_payment` checkout; only
  /// present on the fresh join response (never persisted on list reads).
  final String? clientSecret;
  final CheckInStatus checkInStatus;
  final DateTime? checkInTime;

  const Booking({
    required this.id,
    required this.dinner,
    required this.user,
    required this.seats,
    required this.subtotal,
    required this.serviceFee,
    this.discount = 0,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    this.qrCode,
    this.promoCode,
    this.guestName,
    this.guestEmail,
    this.guestPhone,
    this.paymentMethod = kDefaultPaymentMethod,
    this.paymentStatus = '',
    this.clientSecret,
    this.checkInStatus = CheckInStatus.notCheckedIn,
    this.checkInTime,
  });

  /// The seat is held but the guest never confirmed the card in Stripe.
  bool get isAwaitingPayment => paymentStatus == 'pending_payment';

  /// Checkout died at the gateway (declined/abandoned-and-swept).
  bool get isPaymentFailed => paymentStatus == 'failed';

  /// Normalised payment state. `payment_status` wins; legacy rows that carry
  /// no gateway status are mapped from the booking lifecycle instead.
  BookingPaymentState get paymentState {
    switch (paymentStatus) {
      case 'paid':
      case 'authorized':
        return BookingPaymentState.paid;
      case 'refunded':
        return BookingPaymentState.refunded;
      case 'failed':
        return BookingPaymentState.failed;
      case 'pending_payment':
        return BookingPaymentState.pending;
    }
    switch (status) {
      case BookingStatus.refunded:
        return BookingPaymentState.refunded;
      case BookingStatus.cancelled:
        return BookingPaymentState.notCharged;
      case BookingStatus.pending:
        return BookingPaymentState.pending;
      case BookingStatus.confirmed:
      case BookingStatus.completed:
      case BookingStatus.noShow:
        return BookingPaymentState.paid;
    }
  }

  /// Short label for the normalised payment state.
  String get paymentStateLabel {
    switch (paymentState) {
      case BookingPaymentState.paid:
        return 'Paid';
      case BookingPaymentState.pending:
        return 'Pending';
      case BookingPaymentState.failed:
        return 'Failed';
      case BookingPaymentState.refunded:
        return 'Refunded';
      case BookingPaymentState.notCharged:
        return 'Not charged';
    }
  }

  /// Masked payment method safe to display. Never fabricates a card when the
  /// server recorded none.
  String get paymentMethodLabel =>
      paymentMethod.trim().isEmpty ? 'Not recorded' : paymentMethod;

  /// Booking reference shown on receipts and in the payment ledger.
  String get reference => (qrCode != null && qrCode!.isNotEmpty) ? qrCode! : id;

  /// ISO currency code for this booking's amounts.
  ///
  /// The backend settles in a single currency today and does not serialise a
  /// code, so this defaults to [kDefaultCurrency]. It exists so aggregation
  /// logic groups by currency instead of assuming one.
  String get currencyCode => kDefaultCurrency;

  String get statusLabel {
    switch (status) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.noShow:
        return 'No-show';
      case BookingStatus.refunded:
        return 'Refunded';
    }
  }

  String get formattedTotal => formatMoney(totalAmount, currency: currencyCode);
  String get formattedSubtotal => formatMoney(subtotal, currency: currencyCode);
  String get formattedServiceFee =>
      formatMoney(serviceFee, currency: currencyCode);
  String get formattedDiscount => discount > 0
      ? '-${formatMoney(discount, currency: currencyCode)}'
      : formatMoney(0, currency: currencyCode);

  String get checkInStatusLabel {
    switch (checkInStatus) {
      case CheckInStatus.notCheckedIn:
        return 'Not checked in';
      case CheckInStatus.checkedIn:
        return 'Checked in';
      case CheckInStatus.expired:
        return 'Expired';
    }
  }

  String? get formattedCheckInTime {
    if (checkInTime == null) return null;
    return formatVenueTime(checkInTime!);
  }

  /// Whether this booking still belongs under "Upcoming" when compared at
  /// [now]. As with table reservations a live status alone is not enough: a
  /// `confirmed` booking for an event that has already started must not sit in
  /// the Upcoming tab, or the app appears to accept bookings in the past.
  bool isUpcomingAt(DateTime now) {
    final live = status == BookingStatus.confirmed ||
        status == BookingStatus.pending;
    return live && dinner.dateTime.isAfter(now);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Booking && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
