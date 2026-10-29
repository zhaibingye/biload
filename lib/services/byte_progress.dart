class ByteProgress {
  ByteProgress(List<int?> expected)
    : sizes = expected.map((n) => n != null && n > 0 ? n : null).toList(),
      downloaded = List.filled(expected.length, 0);

  final List<int?> sizes;
  final List<int> downloaded;
  int get downloadedBytes => downloaded.fold(0, (a, b) => a + b);
  int? get totalBytes =>
      sizes.any((n) => n == null) ? null : sizes.fold<int>(0, (a, b) => a + b!);
  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : (downloadedBytes / totalBytes!).clamp(0, 1);

  void update(int index, double? fraction, {int? expectedSize}) {
    if (expectedSize != null && expectedSize > 0) sizes[index] = expectedSize;
    final size = sizes[index];
    if (size != null && fraction != null && fraction >= 0 && fraction <= 1) {
      downloaded[index] = (size * fraction).floor().clamp(0, size);
    }
  }

  void complete(int index, int actualSize) {
    sizes[index] = actualSize;
    downloaded[index] = actualSize;
  }
}
