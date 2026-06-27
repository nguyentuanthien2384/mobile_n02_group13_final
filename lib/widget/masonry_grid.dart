import 'package:flutter/material.dart';

/// Lưới masonry 2 cột (so le chiều cao) không cần thư viện ngoài.
class MasonryTwoColumn extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final EdgeInsetsGeometry padding;

  const MasonryTwoColumn({
    super.key,
    required this.children,
    this.spacing = 12,
    this.padding = const EdgeInsets.fromLTRB(12, 4, 12, 96),
  });

  @override
  Widget build(BuildContext context) {
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      final w = Padding(
        padding: EdgeInsets.only(bottom: spacing),
        child: children[i],
      );
      (i.isEven ? left : right).add(w);
    }

    return SingleChildScrollView(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: left)),
          SizedBox(width: spacing),
          Expanded(child: Column(children: right)),
        ],
      ),
    );
  }
}
