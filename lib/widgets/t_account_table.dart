import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TAccountTable extends StatelessWidget {
  final String title;
  final Color headerColor;
  final List<MapEntry<String, int>> leftItems;
  final List<MapEntry<String, int>> rightItems;
  final int leftTotal;
  final int rightTotal;

  const TAccountTable({
    super.key,
    required this.title,
    required this.headerColor,
    required this.leftItems,
    required this.rightItems,
    required this.leftTotal,
    required this.rightTotal,
  });

  @override
  Widget build(BuildContext context) {
    // ★ここに 'fmt' がありましたが、使っていないので削除しました
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant;

    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 2,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildColumn(context, leftItems, leftTotal)),
                VerticalDivider(width: 1, thickness: 1, color: borderColor),
                Expanded(child: _buildColumn(context, rightItems, rightTotal)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(BuildContext context, List<MapEntry<String, int>> items, int total) {
    final fmt = NumberFormat("#,###"); // ★こっちで使っているのでOKです
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 項目リスト
        ...items.map((e) {
          final isSummary = e.key == '純資産' || e.key == '当期純利益' || e.key == '当期純損失';
          final textColor = isSummary ? colorScheme.primary : colorScheme.onSurface;
          final fontWeight = isSummary ? FontWeight.bold : FontWeight.normal;
          
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(e.key, style: TextStyle(fontSize: 12, fontWeight: fontWeight, color: textColor), overflow: TextOverflow.ellipsis)),
                Text(fmt.format(e.value), style: TextStyle(fontSize: 12, fontWeight: fontWeight, color: textColor)),
              ],
            ),
          );
        }),
        const Spacer(),
        // 合計行
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("計", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Text(fmt.format(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline)),
            ],
          ),
        ),
      ],
    );
  }
}