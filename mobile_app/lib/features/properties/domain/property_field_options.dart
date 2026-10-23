const propertyAreaUnitLabels = <String, String>{
  'sqm': 'متر مربع',
  'libna_sanaani': 'لبنة صنعاني',
  'libna_dhamari': 'لبنة ذمار',
  'qasaba_taizi_ashari': 'قصبة تعزي عشاري',
  'qasaba_taizi_hadawi': 'قصبة تعزي هذوي',
  'qasaba_ibbi': 'قصبة إبي',
};

const propertyAreaUnitSquareMetres = <String, double>{
  'sqm': 1,
  'libna_sanaani': 44.44,
  'libna_dhamari': 114.49,
  'qasaba_taizi_ashari': 20.25,
  'qasaba_taizi_hadawi': 29.16,
  'qasaba_ibbi': 56.25,
};

const propertyFacadeLabels = <String, String>{
  'north': 'شمالية',
  'south': 'جنوبية',
  'east': 'شرقية',
  'west': 'غربية',
  'northeast': 'شمالية شرقية',
  'northwest': 'شمالية غربية',
  'southeast': 'جنوبية شرقية',
  'southwest': 'جنوبية غربية',
  'multiple': 'أكثر من واجهة',
};

String propertyAreaUnitLabel(String? value) =>
    propertyAreaUnitLabels[value] ?? 'متر مربع';

String propertyFacadeLabel(String? value) =>
    propertyFacadeLabels[value] ?? 'غير محددة';

String formatPropertyAreaValue(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
