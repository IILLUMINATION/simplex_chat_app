import 'dart:math' as math;

/// Which edges of a mosaic tile lie on the outer border of the whole group.
/// Telegram uses these to round only the outer corners and to add the 4 px
/// skip on the inside edges (`RectPart` in `grouped_layout.h`).
enum MediaSide { top, left, right, bottom }

class GroupedMediaLayout {
  const GroupedMediaLayout({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.sides,
  });

  final int left;
  final int top;
  final int width;
  final int height;
  final Set<MediaSide> sides;

  bool has(MediaSide side) => sides.contains(side);

  int get right => left + width;
  int get bottom => top + height;
}

/// `st::historyGroupWidthMax` = `maxMediaSize` (`chat.style:169,508`).
const int groupedMediaWidthMax = 430;

/// `st::historyGroupWidthMin` = `minPhotoSize` (`chat.style:168,509`).
const int groupedMediaWidthMin = 100;

/// `st::historyGroupSkip` (`chat.style:510`).
const int groupedMediaSkip = 4;

/// `GroupedMedia::kMaxSize` (`history_view_media_grouped.h:22`).
const int groupedMediaMaxCount = 10;

/// Port of `Ui::LayoutMediaGroup` from
/// `telegram-desktop/Telegram/SourceFiles/ui/grouped_layout.cpp:126`.
/// `ratios` are width/height of every tile; the caller feeds the natural photo
/// sizes the same way `Photo::sizeForGroupingOptimal` does.
List<GroupedMediaLayout> layoutMediaGroup(
  List<double> ratios, {
  int maxWidth = groupedMediaWidthMax,
  int minWidth = groupedMediaWidthMin,
  int spacing = groupedMediaSkip,
}) {
  return _Layouter(ratios, maxWidth, minWidth, spacing).layout();
}

/// `GroupedMedia::countCurrentSize` (`history_view_media_grouped.cpp:208`)
/// lays the grid out at the maximal width and scales it down for narrow
/// bubbles. Spacing scales with the geometry so the gaps stay proportional.
List<GroupedMediaLayout> scaleGroupLayout(
  List<GroupedMediaLayout> layout,
  int width, {
  int spacing = groupedMediaSkip,
}) {
  final factor = width / groupedMediaWidthMax;
  int scale(int value) => (value * factor).round();
  final scaledSpacing = scale(spacing);
  final scaled = <GroupedMediaLayout>[];
  for (final tile in layout) {
    final needRightSkip = !tile.has(MediaSide.right);
    final needBottomSkip = !tile.has(MediaSide.bottom);
    final left = scale(tile.left);
    final top = scale(tile.top);
    final right = scale(tile.right + (needRightSkip ? spacing : 0));
    final bottom = scale(tile.bottom + (needBottomSkip ? spacing : 0));
    scaled.add(
      GroupedMediaLayout(
        left: left,
        top: top,
        width: right - left - (needRightSkip ? scaledSpacing : 0),
        height: bottom - top - (needBottomSkip ? scaledSpacing : 0),
        sides: tile.sides,
      ),
    );
  }
  return scaled;
}

int _round(double value) => value.round();

class _Layouter {
  _Layouter(this.ratios, this.maxWidth, this.minWidth, this.spacing)
    : count = ratios.length,
      maxHeight = maxWidth,
      // Upstream seeds the sum with 1.0 before dividing by the count.
      averageRatio =
          (ratios.fold<double>(1, (sum, ratio) => sum + ratio)) /
          math.max(ratios.length, 1),
      proportions = ratios
          .map((ratio) => ratio > 1.2 ? 'w' : (ratio < 0.8 ? 'n' : 'q'))
          .join();

  final List<double> ratios;
  final int maxWidth;
  final int minWidth;
  final int spacing;
  final int count;
  final int maxHeight;
  final double averageRatio;
  final String proportions;

  /// `_maxWidth / _maxHeight`; always 1 for the square first pass.
  double get maxSizeRatio => maxWidth / maxHeight;

  List<GroupedMediaLayout> layout() {
    if (count == 0) return const [];
    if (count == 1) return _layoutOne();
    if (count >= 5 || ratios.any((ratio) => ratio > 2)) {
      return _ComplexLayouter(
        ratios,
        averageRatio,
        maxWidth,
        minWidth,
        spacing,
      ).layout();
    }
    if (count == 2) return _layoutTwo();
    if (count == 3) return _layoutThree();
    return _layoutFour();
  }

  List<GroupedMediaLayout> _layoutTwo() {
    if (proportions == 'ww' &&
        averageRatio > 1.4 * maxSizeRatio &&
        (ratios[1] - ratios[0]).abs() < 0.2) {
      return _layoutTwoTopBottom();
    } else if (proportions == 'ww' || proportions == 'qq') {
      return _layoutTwoLeftRightEqual();
    }
    return _layoutTwoLeftRight();
  }

  List<GroupedMediaLayout> _layoutThree() {
    if (proportions[0] == 'n') return _layoutThreeLeftAndOther();
    return _layoutThreeTopAndOther();
  }

  List<GroupedMediaLayout> _layoutFour() {
    if (proportions[0] == 'w') return _layoutFourTopAndOther();
    return _layoutFourLeftAndOther();
  }

  List<GroupedMediaLayout> _layoutOne() {
    final width = maxWidth;
    final height = _round(width / ratios[0]);
    return [
      GroupedMediaLayout(
        left: 0,
        top: 0,
        width: width,
        height: height,
        sides: const {
          MediaSide.left,
          MediaSide.top,
          MediaSide.right,
          MediaSide.bottom,
        },
      ),
    ];
  }

  List<GroupedMediaLayout> _layoutTwoTopBottom() {
    final width = maxWidth;
    final height = _round(
      math.min(
        width / ratios[0],
        math.min(width / ratios[1], (maxHeight - spacing) / 2),
      ),
    );
    return [
      GroupedMediaLayout(
        left: 0,
        top: 0,
        width: width,
        height: height,
        sides: const {MediaSide.left, MediaSide.top, MediaSide.right},
      ),
      GroupedMediaLayout(
        left: 0,
        top: height + spacing,
        width: width,
        height: height,
        sides: const {MediaSide.left, MediaSide.right, MediaSide.bottom},
      ),
    ];
  }

  List<GroupedMediaLayout> _layoutTwoLeftRightEqual() {
    final width = (maxWidth - spacing) ~/ 2;
    final height = _round(
      math.min(
        width / ratios[0],
        math.min(width / ratios[1], maxHeight.toDouble()),
      ),
    );
    return [
      GroupedMediaLayout(
        left: 0,
        top: 0,
        width: width,
        height: height,
        sides: const {MediaSide.top, MediaSide.left, MediaSide.bottom},
      ),
      GroupedMediaLayout(
        left: width + spacing,
        top: 0,
        width: width,
        height: height,
        sides: const {MediaSide.top, MediaSide.right, MediaSide.bottom},
      ),
    ];
  }

  List<GroupedMediaLayout> _layoutTwoLeftRight() {
    final minimalWidth = _round(minWidth * 1.5);
    final secondWidth = math.min(
      _round(
        math.max(
          0.4 * (maxWidth - spacing),
          (maxWidth - spacing) /
              ratios[0] /
              (1 / ratios[0] + 1 / ratios[1]),
        ),
      ),
      maxWidth - spacing - minimalWidth,
    );
    final firstWidth = maxWidth - secondWidth - spacing;
    final height = math.min(
      maxHeight,
      _round(math.min(firstWidth / ratios[0], secondWidth / ratios[1])),
    );
    return [
      GroupedMediaLayout(
        left: 0,
        top: 0,
        width: firstWidth,
        height: height,
        sides: const {MediaSide.top, MediaSide.left, MediaSide.bottom},
      ),
      GroupedMediaLayout(
        left: firstWidth + spacing,
        top: 0,
        width: secondWidth,
        height: height,
        sides: const {MediaSide.top, MediaSide.right, MediaSide.bottom},
      ),
    ];
  }

  List<GroupedMediaLayout> _layoutThreeLeftAndOther() {
    final firstHeight = maxHeight;
    final thirdHeight = _round(
      math.min(
        (maxHeight - spacing) / 2,
        ratios[1] * (maxWidth - spacing) / (ratios[2] + ratios[1]),
      ),
    );
    final secondHeight = firstHeight - thirdHeight - spacing;
    final rightWidth = math.max(
      minWidth,
      _round(
        math.min(
          (maxWidth - spacing) / 2,
          math.min(thirdHeight * ratios[2], secondHeight * ratios[1]),
        ),
      ),
    );
    final leftWidth = math.min(
      _round(firstHeight * ratios[0]),
      maxWidth - spacing - rightWidth,
    );
    return [
      GroupedMediaLayout(
        left: 0,
        top: 0,
        width: leftWidth,
        height: firstHeight,
        sides: const {MediaSide.top, MediaSide.left, MediaSide.bottom},
      ),
      GroupedMediaLayout(
        left: leftWidth + spacing,
        top: 0,
        width: rightWidth,
        height: secondHeight,
        sides: const {MediaSide.top, MediaSide.right},
      ),
      GroupedMediaLayout(
        left: leftWidth + spacing,
        top: secondHeight + spacing,
        width: rightWidth,
        height: thirdHeight,
        sides: const {MediaSide.bottom, MediaSide.right},
      ),
    ];
  }

  List<GroupedMediaLayout> _layoutThreeTopAndOther() {
    final firstWidth = maxWidth;
    final firstHeight = _round(
      math.min(firstWidth / ratios[0], (maxHeight - spacing) * 0.66),
    );
    final secondWidth = (maxWidth - spacing) ~/ 2;
    final secondHeight = math.min(
      maxHeight - firstHeight - spacing,
      _round(math.min(secondWidth / ratios[1], secondWidth / ratios[2])),
    );
    final thirdWidth = firstWidth - secondWidth - spacing;
    return [
      GroupedMediaLayout(
        left: 0,
        top: 0,
        width: firstWidth,
        height: firstHeight,
        sides: const {MediaSide.left, MediaSide.top, MediaSide.right},
      ),
      GroupedMediaLayout(
        left: 0,
        top: firstHeight + spacing,
        width: secondWidth,
        height: secondHeight,
        sides: const {MediaSide.bottom, MediaSide.left},
      ),
      GroupedMediaLayout(
        left: secondWidth + spacing,
        top: firstHeight + spacing,
        width: thirdWidth,
        height: secondHeight,
        sides: const {MediaSide.bottom, MediaSide.right},
      ),
    ];
  }

  List<GroupedMediaLayout> _layoutFourTopAndOther() {
    final w = maxWidth;
    final h0 = _round(
      math.min(w / ratios[0], (maxHeight - spacing) * 0.66),
    );
    final h = _round(
      (maxWidth - 2 * spacing) / (ratios[1] + ratios[2] + ratios[3]),
    );
    final w0 = math.max(
      minWidth,
      _round(math.min((maxWidth - 2 * spacing) * 0.4, h * ratios[1])),
    );
    final w2 = _round(
      math.max(
        math.max(minWidth.toDouble(), (maxWidth - 2 * spacing) * 0.33),
        h * ratios[3],
      ),
    );
    final w1 = w - w0 - w2 - 2 * spacing;
    final h1 = math.min(maxHeight - h0 - spacing, h);
    return [
      GroupedMediaLayout(
        left: 0,
        top: 0,
        width: w,
        height: h0,
        sides: const {MediaSide.left, MediaSide.top, MediaSide.right},
      ),
      GroupedMediaLayout(
        left: 0,
        top: h0 + spacing,
        width: w0,
        height: h1,
        sides: const {MediaSide.bottom, MediaSide.left},
      ),
      GroupedMediaLayout(
        left: w0 + spacing,
        top: h0 + spacing,
        width: w1,
        height: h1,
        sides: const {MediaSide.bottom},
      ),
      GroupedMediaLayout(
        left: w0 + w1 + 2 * spacing,
        top: h0 + spacing,
        width: w2,
        height: h1,
        sides: const {MediaSide.right, MediaSide.bottom},
      ),
    ];
  }

  List<GroupedMediaLayout> _layoutFourLeftAndOther() {
    final h = maxHeight;
    final w0 = _round(
      math.min(h * ratios[0], (maxWidth - spacing) * 0.6),
    );
    final w = _round(
      (maxHeight - 2 * spacing) /
          (1 / ratios[1] + 1 / ratios[2] + 1 / ratios[3]),
    );
    final h0 = _round(w / ratios[1]);
    final h1 = _round(w / ratios[2]);
    final h2 = h - h0 - h1 - 2 * spacing;
    final w1 = math.max(
      minWidth,
      math.min(maxWidth - w0 - spacing, w),
    );
    return [
      GroupedMediaLayout(
        left: 0,
        top: 0,
        width: w0,
        height: h,
        sides: const {MediaSide.top, MediaSide.left, MediaSide.bottom},
      ),
      GroupedMediaLayout(
        left: w0 + spacing,
        top: 0,
        width: w1,
        height: h0,
        sides: const {MediaSide.top, MediaSide.right},
      ),
      GroupedMediaLayout(
        left: w0 + spacing,
        top: h0 + spacing,
        width: w1,
        height: h1,
        sides: const {MediaSide.right},
      ),
      GroupedMediaLayout(
        left: w0 + spacing,
        top: h0 + h1 + 2 * spacing,
        width: w1,
        height: h2,
        sides: const {MediaSide.bottom, MediaSide.right},
      ),
    ];
  }
}

/// Port of `ComplexLayouter` (`grouped_layout.cpp:300`): splits ≥5 tiles —
/// or a group with a panorama — into 2–4 rows and keeps the split whose total
/// height lands closest to the 4:3 cap.
class _ComplexLayouter {
  _ComplexLayouter(
    List<double> ratios,
    this.averageRatio,
    this.maxWidth,
    this.minWidth,
    this.spacing,
  ) : ratios = _cropRatios(ratios, averageRatio),
      maxHeight = (maxWidth * 4) ~/ 3;

  final List<double> ratios;
  final double averageRatio;
  final int maxWidth;
  final int maxHeight;
  final int minWidth;
  final int spacing;

  static List<double> _cropRatios(List<double> ratios, double averageRatio) {
    const maxRatio = 2.75;
    const minRatio = 0.6667;
    return [
      for (final ratio in ratios)
        averageRatio > 1.1
            ? ratio.clamp(1.0, maxRatio)
            : ratio.clamp(minRatio, 1.0),
    ];
  }

  List<GroupedMediaLayout> layout() {
    final count = ratios.length;
    final attempts = <_Attempt>[];

    double multiHeight(int offset, int lineCount) {
      final sum = ratios
          .skip(offset)
          .take(lineCount)
          .fold<double>(0, (total, ratio) => total + ratio);
      return (maxWidth - (lineCount - 1) * spacing) / sum;
    }

    void pushAttempt(List<int> lineCounts) {
      final heights = <double>[];
      var offset = 0;
      for (final lineCount in lineCounts) {
        heights.add(multiHeight(offset, lineCount));
        offset += lineCount;
      }
      attempts.add(_Attempt(lineCounts, heights));
    }

    for (var first = 1; first < count; first++) {
      final second = count - first;
      if (first > 3 || second > 3) continue;
      pushAttempt([first, second]);
    }
    for (var first = 1; first < count - 1; first++) {
      for (var second = 1; second < count - first; second++) {
        final third = count - first - second;
        if (first > 3 ||
            second > (averageRatio < 0.85 ? 4 : 3) ||
            third > 3) {
          continue;
        }
        pushAttempt([first, second, third]);
      }
    }
    for (var first = 1; first < count - 1; first++) {
      for (var second = 1; second < count - first; second++) {
        for (var third = 1; third < count - first - second; third++) {
          final fourth = count - first - second - third;
          if (first > 3 || second > 3 || third > 3 || fourth > 3) continue;
          pushAttempt([first, second, third, fourth]);
        }
      }
    }

    _Attempt? optimal;
    var optimalDiff = 0.0;
    for (final attempt in attempts) {
      final heights = attempt.heights;
      final counts = attempt.lineCounts;
      final totalHeight =
          heights.fold<double>(0, (total, h) => total + h) +
          spacing * (counts.length - 1);
      final minLineHeight = heights.reduce(math.min);
      final bad1 = minLineHeight < minWidth ? 1.5 : 1.0;
      var bad2 = 1.0;
      for (var line = 1; line < counts.length; line++) {
        if (counts[line - 1] > counts[line]) {
          bad2 = 1.5;
          break;
        }
      }
      final diff = (totalHeight - maxHeight).abs() * bad1 * bad2;
      if (optimal == null || diff < optimalDiff) {
        optimal = attempt;
        optimalDiff = diff;
      }
    }
    if (optimal == null) return const [];

    final result = List<GroupedMediaLayout?>.filled(count, null);
    var index = 0;
    var y = 0.0;
    for (var row = 0; row < optimal.lineCounts.length; row++) {
      final colCount = optimal.lineCounts[row];
      final lineHeight = optimal.heights[row];
      final height = _round(lineHeight);
      var x = 0;
      for (var col = 0; col < colCount; col++) {
        final sides = <MediaSide>{
          if (row == 0) MediaSide.top,
          if (row == optimal.lineCounts.length - 1) MediaSide.bottom,
          if (col == 0) MediaSide.left,
          if (col == colCount - 1) MediaSide.right,
        };
        final ratio = ratios[index];
        final width = col == colCount - 1
            ? maxWidth - x
            : _round(ratio * lineHeight);
        result[index] = GroupedMediaLayout(
          left: x,
          top: y.toInt(),
          width: width,
          height: height,
          sides: sides,
        );
        x += width + spacing;
        index++;
      }
      y += height + spacing;
    }
    return result.cast<GroupedMediaLayout>();
  }
}

class _Attempt {
  const _Attempt(this.lineCounts, this.heights);

  final List<int> lineCounts;
  final List<double> heights;
}
