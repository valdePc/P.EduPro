import 'package:flutter/material.dart';

/// Switches between a split workspace and a list/detail flow using actual space.
class SchoolMasterDetailLayout extends StatefulWidget {
  final String? selectedSchoolId;
  final Widget Function(BuildContext context, double width) headerBuilder;
  final Widget Function(BuildContext context, VoidCallback openDetail)
  listBuilder;
  final WidgetBuilder detailBuilder;

  const SchoolMasterDetailLayout({
    super.key,
    required this.selectedSchoolId,
    required this.headerBuilder,
    required this.listBuilder,
    required this.detailBuilder,
  });

  @override
  State<SchoolMasterDetailLayout> createState() =>
      _SchoolMasterDetailLayoutState();
}

class _SchoolMasterDetailLayoutState extends State<SchoolMasterDetailLayout> {
  bool _detailOpen = false;

  @override
  void didUpdateWidget(covariant SchoolMasterDetailLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSchoolId == null) _detailOpen = false;
  }

  void _openDetail() => setState(() => _detailOpen = true);
  void _backToList() => setState(() => _detailOpen = false);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 960;
      final padding = wide ? 24.0 : 12.0;
      final width = constraints.maxWidth - padding * 2;
      final showDetail =
          !wide && _detailOpen && widget.selectedSchoolId != null;
      return PopScope<void>(
        canPop: !showDetail,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && showDetail) _backToList();
        },
        child: Padding(
          padding: EdgeInsets.all(padding),
          child:
              showDetail
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('school-workspace-back'),
                        onPressed: _backToList,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Volver a la lista de colegios'),
                      ),
                      const SizedBox(height: 8),
                      Expanded(child: widget.detailBuilder(context)),
                    ],
                  )
                  : NestedScrollView(
                    headerSliverBuilder:
                        (context, innerBoxIsScrolled) => [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: widget.headerBuilder(context, width),
                            ),
                          ),
                        ],
                    body:
                        wide
                            ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: (width * 0.32).clamp(280.0, 380.0),
                                  child: PrimaryScrollController.none(
                                    child: widget.listBuilder(
                                      context,
                                      _openDetail,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(child: widget.detailBuilder(context)),
                              ],
                            )
                            : widget.listBuilder(context, _openDetail),
                  ),
        ),
      );
    },
  );
}

/// Keeps field values readable instead of reserving most mobile width for labels.
class SchoolDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const SchoolDetailRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final caption = Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w700,
          ),
        );
        final content = Text(
          value.trim().isEmpty ? '-' : value.trim(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [caption, const SizedBox(height: 4), content],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 170, child: caption),
            Expanded(child: content),
          ],
        );
      },
    ),
  );
}

/// Keeps report metrics readable as the available width or text scale changes.
class SchoolMetricGrid extends StatelessWidget {
  final List<Widget> children;
  const SchoolMetricGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (children.isEmpty) return const SizedBox.shrink();
      const gap = 10.0;
      final minimumWidth = MediaQuery.textScalerOf(context).scale(220);
      final columns =
          ((constraints.maxWidth + gap) / (minimumWidth + gap))
              .floor()
              .clamp(1, children.length < 3 ? children.length : 3)
              .toInt();
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
