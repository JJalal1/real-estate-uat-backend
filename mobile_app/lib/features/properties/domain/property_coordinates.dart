/// A stored geographic point, excluding the legacy unspecified (0, 0) value.
bool hasValidPropertyCoordinates(double? latitude, double? longitude) =>
    latitude != null && longitude != null &&
    latitude.isFinite && longitude.isFinite &&
    latitude.abs() <= 90 && longitude.abs() <= 180 &&
    (latitude != 0 || longitude != 0);
