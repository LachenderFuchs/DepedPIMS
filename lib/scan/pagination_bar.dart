import 'package:flutter/material.dart';

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

  // Shared constraints that eliminate the default 48×48 tap-target padding.
  // Without this, each of the 4 IconButton widgets bleeds 14px of invisible
  // space (4 × 14px = 56px total), causing the right-side overflow.
  static const _btnConstraints = BoxConstraints(minWidth: 32, minHeight: 32);

  @override
  Widget build(BuildContext context) {
    final start = totalItems == 0 ? 0 : currentPage * rowsPerPage + 1;
    final end = ((currentPage + 1) * rowsPerPage).clamp(0, totalItems);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            'Showing $start–$end of $totalItems entries',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const Spacer(),
          // ── First page ─────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.first_page),
            tooltip: 'First page',
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: _btnConstraints,
            visualDensity: VisualDensity.compact,
            onPressed: currentPage > 0 ? () => onPageChanged(0) : null,
          ),
          // ── Previous page ──────────────────────────────────────────
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
          // ── Page number chips ──────────────────────────────────────
          ...List.generate(totalPages, (i) => i)
              .where(
                (i) =>
                    i == 0 ||
                    i == totalPages - 1 ||
                    (i - currentPage).abs() <= 1,
              )
              .fold<List<Widget>>([], (acc, i) {
                if (acc.isNotEmpty) {
                  final prev =
                      int.tryParse(
                        (acc.last as dynamic)?.key?.toString() ?? '',
                      ) ??
                      -999;
                  if (i - prev > 1) {
                    acc.add(
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '…',
                          style: TextStyle(color: Colors.grey.shade500),
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
                          color: isActive
                              ? const Color(0xff2F3E46)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xff2F3E46)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                return acc;
              }),
          // ── Next page ──────────────────────────────────────────────
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
          // ── Last page ──────────────────────────────────────────────
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
        ],
      ),
    );
  }
}
