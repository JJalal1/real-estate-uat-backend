String rentalMonths(int months) => switch(months) {
  1 => 'شهر واحد', 2 => 'شهران', >= 3 && <= 10 => '$months أشهر',
  12 => 'سنة واحدة', 24 => 'سنتان', _ => '$months شهرًا',
};

String rentalConditionSummary(Map<String,dynamic> condition) => switch(condition['kind']) {
  'advance' => 'إيجار مقدم: ${rentalMonths((condition['months'] as num? ?? 0).toInt())}',
  'duration' => 'مدة العقد: ${rentalMonths((condition['months'] as num? ?? 0).toInt())}',
  'guarantor' => 'ضمانة تجارية: مطلوبة',
  'deposit' => 'تأمين: مطلوب',
  'special' => 'شرط خاص: ${condition['text'] ?? ''}',
  _ => '',
};
