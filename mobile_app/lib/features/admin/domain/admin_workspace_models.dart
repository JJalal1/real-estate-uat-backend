class AdminDashboardSummary {
  const AdminDashboardSummary({
    required this.usersTotal,
    required this.usersActive,
    required this.pendingListings,
    required this.publishedListings,
    required this.supportOpen,
    required this.supportTicketsOpen,
    required this.reportsOpen,
    required this.supportOverdue,
    required this.bookingsRequested,
    required this.bookingsActive,
    required this.brokerKycPending,
    required this.paymentsPending,
    required this.alerts,
  });

  final int usersTotal;
  final int usersActive;
  final int pendingListings;
  final int publishedListings;
  final int supportOpen;
  final int supportTicketsOpen;
  final int reportsOpen;
  final int supportOverdue;
  final int bookingsRequested;
  final int bookingsActive;
  final int brokerKycPending;
  final int paymentsPending;
  final List<AdminAlertItem> alerts;

  factory AdminDashboardSummary.fromJson(Map<String, dynamic> json) {
    final users = _map(json['users']);
    final listings = _map(json['listings']);
    final support = _map(json['support']);
    final bookings = _map(json['bookings']);
    final supportOpen = _int(support['open']);
    final reportsOpen = _int(support['reports_open']);
    final alerts = json['alerts'] as List<dynamic>? ?? const [];
    return AdminDashboardSummary(
      usersTotal: _int(users['total']),
      usersActive: _int(users['active']),
      pendingListings: _int(listings['pending_review']),
      publishedListings: _int(listings['published']),
      supportOpen: supportOpen,
      supportTicketsOpen: support.containsKey('tickets_open')
          ? _int(support['tickets_open'])
          : (supportOpen > reportsOpen ? supportOpen - reportsOpen : 0),
      reportsOpen: reportsOpen,
      supportOverdue: _int(support['overdue']),
      bookingsRequested: _int(bookings['requested']),
      bookingsActive: _int(bookings['active']),
      brokerKycPending: _int(json['broker_kyc_pending']),
      paymentsPending: _int(json['payments_pending']),
      alerts: alerts
          .whereType<Map<String, dynamic>>()
          .map(AdminAlertItem.fromJson)
          .toList(growable: false),
    );
  }
}

class AdminAlertItem {
  const AdminAlertItem(
      {required this.key,
      required this.label,
      required this.count,
      required this.route});
  final String key;
  final String label;
  final int count;
  final String route;
  factory AdminAlertItem.fromJson(Map<String, dynamic> json) => AdminAlertItem(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        count: _int(json['count']),
        route: json['route']?.toString() ?? '',
      );
}

class PlatformSettingItem {
  const PlatformSettingItem(
      {required this.key,
      required this.labelAr,
      required this.group,
      required this.valueType,
      required this.value});
  final String key;
  final String labelAr;
  final String group;
  final String valueType;
  final dynamic value;
  factory PlatformSettingItem.fromJson(Map<String, dynamic> json) =>
      PlatformSettingItem(
        key: json['key']?.toString() ?? '',
        labelAr: json['label_ar']?.toString() ?? '',
        group: json['group']?.toString() ?? 'general',
        valueType: json['value_type']?.toString() ?? 'string',
        value: json['value'],
      );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};
int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
