import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable pagination bar used by WFP Management, Budget Overview,
/// and Reports pages.
class PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int rowsPerPage;
  final void Function(int) onPageChanged;

  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.rowsPerPage,
    required this.onPageChanged,
  });

  // Shared constraints that eliminate the default 48x48 tap-target padding.
  static const _btnConstraints = BoxConstraints(minWidth: 32, minHeight: 32);

  @override
  Widget build(BuildContext context) {
    final start = totalItems == 0 ? 0 : currentPage * rowsPerPage + 1;
    final end = ((currentPage + 1) * rowsPerPage).clamp(0, totalItems);
    final pageControls = <Widget>[
      IconButton(
        icon: const Icon(Icons.first_page),
        tooltip: 'First page',
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: _btnConstraints,
        visualDensity: VisualDensity.compact,
        onPressed: currentPage > 0 ? () => onPageChanged(0) : null,
      ),
      IconButton(
        icon: const Icon(Icons.chevron_left),
        tooltip: 'Previous page',
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: _btnConstraints,
        visualDensity: VisualDensity.compact,
        onPressed: currentPage > 0
            ? () => onPageChanged(currentPage - 1)
            : null,
      ),
      ...List.generate(totalPages, (i) => i)
          .where(
            (i) =>
                i == 0 || i == totalPages - 1 || (i - currentPage).abs() <= 1,
          )
          .fold<List<Widget>>([], (acc, i) {
            if (acc.isNotEmpty) {
              final prev =
                  int.tryParse((acc.last as dynamic)?.key?.toString() ?? '') ??
                  -999;
              if (i - prev > 1) {
                acc.add(
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '...',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                );
              }
            }
            final isActive = i == currentPage;
            acc.add(
              Padding(
                key: ValueKey(i),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  onTap: () => onPageChanged(i),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isActive ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            );
            return acc;
          }),
      IconButton(
        icon: const Icon(Icons.chevron_right),
        tooltip: 'Next page',
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: _btnConstraints,
        visualDensity: VisualDensity.compact,
        onPressed: currentPage < totalPages - 1
            ? () => onPageChanged(currentPage + 1)
            : null,
      ),
      IconButton(
        icon: const Icon(Icons.last_page),
        tooltip: 'Last page',
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: _btnConstraints,
        visualDensity: VisualDensity.compact,
        onPressed: currentPage < totalPages - 1
            ? () => onPageChanged(totalPages - 1)
            : null,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final controls = Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: pageControls,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Showing $start-$end of $totalItems entries',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: controls,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Text(
                  'Showing $start-$end of $totalItems entries',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: controls,
              ),
            ],
          );
        },
      ),
    );
  }
}
