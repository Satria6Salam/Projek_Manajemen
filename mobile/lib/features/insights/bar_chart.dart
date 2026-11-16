import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';

/// Grafik batang sederhana (tanpa paket tambahan).
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.highlightIndex,
    this.height = 140,
    this.showEveryNthLabel = 1,
    this.format,
  });

  /// Format nilai untuk label & tooltip (default: Rupiah).
  final String Function(double value)? format;

  String _fmt(double v) => format != null ? format!(v) : Fmt.rupiah(v.round());

  final List<double> values;
  final List<String> labels;
  final int? highlightIndex;
  final double height;

  /// Tampilkan label setiap n batang (agar 31 tanggal tetap terbaca).
  final int showEveryNthLabel;

  @override
  Widget build(BuildContext context) {
    final double maxValue = values.fold<double>(0, (m, v) => v > m ? v : m);
    final int peak = maxValue > 0 ? values.indexOf(maxValue) : -1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (maxValue > 0)
          Text('Tertinggi ${_fmt(maxValue)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
        const SizedBox(height: 6),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < values.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${labels[i]}: ${_fmt(values[i])}',
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: values.length > 20 ? 1 : 3),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          widthFactor: 1,
                          heightFactor: maxValue > 0
                              ? (values[i] / maxValue).clamp(0.0, 1.0) * 0.95 +
                                  0.02
                              : 0.02,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: i == highlightIndex
                                  ? AppColors.primaryDark
                                  : (i == peak
                                      ? AppColors.primary
                                      : AppColors.primary
                                          .withValues(alpha: 0.45)),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (int i = 0; i < labels.length; i++)
              Expanded(
                child: Text(
                  i % showEveryNthLabel == 0 || i == labels.length - 1
                      ? labels[i]
                      : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: i == highlightIndex
                        ? AppColors.primaryDark
                        : AppColors.textGrey,
                    fontWeight:
                        i == highlightIndex ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
