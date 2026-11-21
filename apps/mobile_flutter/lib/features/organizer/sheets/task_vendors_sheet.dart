import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_icons.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/enums.dart';
import '../../../models/roadmap.dart';
import '../../../models/vendor.dart';
import '../../../models/vendor_labels.dart';
import '../../../shared/widgets/error_retry.dart';
import '../../vendor/vendor_providers.dart';
import '../../vendor/vendor_repository.dart';
import '../widgets/vendor_card.dart';
import 'sheet_scaffold.dart';

/// What the user chose in the task sheet.
sealed class TaskVendorsResult {
  const TaskVendorsResult();
}

class TaskEditRequested extends TaskVendorsResult {
  const TaskEditRequested();
}

class TaskVendorChosen extends TaskVendorsResult {
  const TaskVendorChosen(this.vendorId);
  final String vendorId;
}

/// Planning-only steps that no vendor category covers.
const _noVendorCategories = {'legal_documentation', 'guest_logistics'};

/// A roadmap task with the vendors that fit it. Editing is behind the Edit button.
Future<TaskVendorsResult?> showTaskVendorsSheet(
  BuildContext context, {
  required TaskWithDependencies task,
  String? region,
  double? budget,
}) => showAppSheet<TaskVendorsResult>(
  context,
  (_) => TaskVendorsSheet(task: task, region: region, budget: budget),
);

class TaskVendorsSheet extends ConsumerStatefulWidget {
  const TaskVendorsSheet({super.key, required this.task, this.region, this.budget});

  final TaskWithDependencies task;

  /// The event's region; vendors are narrowed to it (can be switched off).
  final String? region;

  /// What this event set aside for the task's category, if anything.
  final double? budget;

  @override
  ConsumerState<TaskVendorsSheet> createState() => _TaskVendorsSheetState();
}

class _TaskVendorsSheetState extends ConsumerState<TaskVendorsSheet> {
  final _search = TextEditingController();
  VendorPriceTier? _tier;
  late bool _nearMe = widget.region != null && widget.region!.trim().isNotEmpty;
  bool _withinBudget = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _hasVendors => !_noVendorCategories.contains(widget.task.categoryKey);

  VendorFilters get _filters => VendorFilters(
    category: widget.task.categoryKey,
    priceTier: _tier,
    region: _nearMe ? widget.region!.trim() : null,
  );

  List<Vendor> _narrow(List<Vendor> all) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final v in all)
        if ((q.isEmpty || (v.businessName ?? '').toLowerCase().contains(q)) &&
            (!_withinBudget || widget.budget == null || v.startingPrice == null || v.startingPrice! <= widget.budget!))
          v,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final task = widget.task;
    final label = vendorCategoryLabel(task.categoryKey);
    return SheetFrame(
      title: task.name,
      subtitle: '${taskStatusLabel(task.status)} · ${dueLabel(task.dueDate)}',
      footer: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).pop(const TaskEditRequested()),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit task'),
      ),
      children: [
        if (!_hasVendors)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.l),
            child: Text(
              'This step is something you handle yourself, so there are no vendors for it.',
              style: text.bodyMedium,
            ),
          )
        else ...[
          Row(
            children: [
              Icon(categoryIcon(task.categoryKey), size: 20, color: AppColors.maroon),
              const SizedBox(width: AppSpace.s),
              Expanded(child: Text('$label vendors', style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: AppSpace.m),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search by name',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpace.s),
          Wrap(
            spacing: AppSpace.s,
            runSpacing: AppSpace.s,
            children: [
              if (widget.region != null && widget.region!.trim().isNotEmpty)
                FilterChip(
                  label: Text('In ${widget.region!.trim()}'),
                  selected: _nearMe,
                  showCheckmark: false,
                  onSelected: (on) => setState(() => _nearMe = on),
                ),
              if (widget.budget != null)
                FilterChip(
                  label: Text('Within ${formatInr(widget.budget!)}'),
                  selected: _withinBudget,
                  showCheckmark: false,
                  onSelected: (on) => setState(() => _withinBudget = on),
                ),
              for (final t in VendorPriceTier.values)
                ChoiceChip(
                  label: Text(vendorPriceTierLabels[t]!),
                  selected: _tier == t,
                  showCheckmark: false,
                  onSelected: (on) => setState(() => _tier = on ? t : null),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.m),
          ref.watch(vendorsProvider(_filters)).when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => ErrorRetry(
              message: 'Could not load vendors.',
              onRetry: () => ref.invalidate(vendorsProvider(_filters)),
            ),
            data: (all) {
              final vendors = _narrow(all);
              if (vendors.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.l),
                  child: Text(
                    all.isEmpty && _nearMe
                        ? 'No $label vendors in ${widget.region!.trim()} yet. Turn off the place filter to see all.'
                        : 'No vendors match. Try changing the filters.',
                    style: text.bodyMedium,
                  ),
                );
              }
              return Column(
                children: [
                  for (final v in vendors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.m),
                      child: VendorCard(
                        vendor: v,
                        onTap: () => Navigator.of(context).pop(TaskVendorChosen(v.id)),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
