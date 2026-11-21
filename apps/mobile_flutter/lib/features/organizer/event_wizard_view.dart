import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/enums.dart';
import '../../models/event_profile.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/bottom_action_bar.dart';
import '../../shared/widgets/brand_mark.dart';
import '../../shared/widgets/location_picker.dart';
import '../../shared/widgets/primary_button.dart';
import 'event_draft.dart';
import 'organizer_type_info.dart';
import 'sheets/sheet_scaffold.dart' show parseAmount;

const _typeHints = {
  EventType.wedding: 'Rituals, functions and families coming together',
  EventType.birthday: 'A party for a little one or a big milestone',
  EventType.corporate: 'Conference, offsite, launch or team party',
  EventType.funeral: 'A gentle send-off, with care for every detail',
  EventType.engagementOnly: 'The ring ceremony and the celebration around it',
  EventType.custom: 'Something else. Tell us and we will build the plan',
};

const _typeIcons = {
  EventType.wedding: Icons.favorite_border,
  EventType.birthday: Icons.cake_outlined,
  EventType.corporate: Icons.business_center_outlined,
  EventType.funeral: Icons.local_florist_outlined,
  EventType.engagementOnly: Icons.diamond_outlined,
  EventType.custom: Icons.tune,
};

/// Answer key holding the lower end of a custom budget range.
const budgetMinKey = 'budgetMin';

/// Style answer meaning "I'll set my own amount"; mapped to a real tier on submit.
const customTierValue = 'custom';

/// Picks the nearest budget style for a per-guest spend (₹), for the custom style.
BudgetTier tierForPerGuest(double perGuest) {
  if (perGuest < 3000) return BudgetTier.essential;
  if (perGuest < 8000) return BudgetTier.standard;
  if (perGuest < 20000) return BudgetTier.premium;
  return BudgetTier.luxury;
}

/// What the wizard collected, split the way the create API wants it.
class WizardResult {
  const WizardResult({
    required this.type,
    required this.name,
    required this.region,
    this.religionOrTradition,
    required this.date,
    required this.guests,
    required this.budget,
    required this.tier,
    required this.details,
    this.generatedProfileId,
    this.organizerType,
  });

  final EventType type;
  final String name;
  final String region;
  final String? religionOrTradition;
  final DateTime date;
  final int guests;
  final double budget;
  final BudgetTier tier;
  final Map<String, dynamic> details;
  final String? generatedProfileId;

  /// Who is organizing this event (family, committee, company or just the user).
  final OrganizerType? organizerType;
}

/// Step-by-step event creation. The questions come from the event type's
/// [EventTypeProfile], so each type asks only what matters for it. Step 0 picks
/// the type; the remaining steps are the profile's. [onSubmit] returns an error
/// message to show, or null on success.
class EventWizardView extends StatefulWidget {
  const EventWizardView({
    super.key,
    required this.profiles,
    required this.onSubmit,
    this.today,
    this.onBack,
    this.draft,
    this.onDraftChanged,
    this.onGenerate,
  });

  /// Writes the questions for a custom event from the user's description. Null disables that
  /// step, and custom events then use the basic questions. May throw (the wizard shows a retry).
  final Future<GeneratedProfile> Function(String description)? onGenerate;

  /// Picks up where a saved [draft] left off.
  final WizardDraft? draft;

  /// Called after every change with the current state, or null once the wizard is done.
  final ValueChanged<WizardDraft?>? onDraftChanged;

  final List<EventTypeProfile> profiles;
  final Future<String?> Function(WizardResult result) onSubmit;
  final DateTime? today;
  final VoidCallback? onBack;

  @override
  State<EventWizardView> createState() => _EventWizardViewState();
}

class _EventWizardViewState extends State<EventWizardView> {
  late EventType? _type = widget.draft?.type;
  late GeneratedProfile? _generated = _restoreGenerated();
  late String _description = widget.draft?.description ?? '';
  // The description the current questions were written for. Editing it triggers a rewrite.
  late String? _generatedFor = _generated == null ? null : _description;
  bool _generating = false;
  String? _generateError;
  // 0 = type picker, 1 = describe (custom only), then the profile's steps.
  late int _step = _restoreStep();
  late final Map<String, Object?> _answers = {...?widget.draft?.answers};
  PickedLocation? _location;
  bool _showErrors = false;
  bool _submitting = false;
  String? _error;

  GeneratedProfile? _restoreGenerated() {
    final g = widget.draft?.generated;
    if (g == null) return null;
    try {
      return GeneratedProfile.fromJson(g);
    } catch (_) {
      return null;
    }
  }

  int _restoreStep() {
    final step = widget.draft?.step ?? 0;
    // Questions that were never written cannot be resumed past the describe step.
    final needsGenerated = widget.draft?.type == EventType.custom && widget.onGenerate != null;
    return needsGenerated && _generated == null && step > 1 ? 1 : step;
  }

  void _saveDraft() => widget.onDraftChanged?.call(
        _type == null
            ? null
            : WizardDraft(
                type: _type,
                step: _step,
                answers: Map.of(_answers),
                savedAt: DateTime.now(),
                description: _description.isEmpty ? null : _description,
                generated: _generated?.toJson(),
              ),
      );

  bool get _hasDescribeStep => _type == EventType.custom && widget.onGenerate != null;
  int get _extraSteps => _hasDescribeStep ? 1 : 0;
  bool get _onDescribeStep => _hasDescribeStep && _step == 1;
  WizardStep get _currentStep => _steps[_step - 1 - _extraSteps];

  EventTypeProfile? get _profile {
    final type = _type;
    if (type == null) return null;
    if (type == EventType.custom && _generated != null) return _generated!.profile;
    final wire = enumWireValue(type);
    return widget.profiles.where((p) => p.eventType == wire).firstOrNull ??
        widget.profiles.where((p) => p.eventType == 'custom').firstOrNull;
  }

  /// The organizer kinds this event type allows; a profile that lists none allows all.
  List<OrganizerType> get _organizerOptions {
    final p = _profile;
    if (p == null) return const [];
    final listed = [for (final w in p.organizerOptions) ?organizerTypeFromWire(w)];
    return listed.isEmpty ? OrganizerType.values : listed;
  }

  /// "Who is organizing?" comes first for every event type, built from what the type allows.
  WizardStep? get _organizerStep {
    final options = _organizerOptions;
    if (options.length < 2) return null;
    return WizardStep(
      id: 'organizer',
      title: 'Who is organizing?',
      subtitle: 'This decides how your team works together on the event.',
      questions: [
        Question(
          key: organizerQuestionKey,
          label: 'Who is organizing?',
          kind: QuestionKind.singleSelect,
          required: true,
          mapsTo: organizerQuestionKey,
          options: [for (final t in options) QuestionOption(value: t.name, label: organizerTypeInfo[t]!.title)],
        ),
      ],
    );
  }

  /// The chosen organizer kind, or the event type's default until the user picks one.
  String? get _organizerChoice {
    final picked = _answers[organizerQuestionKey];
    if (picked is String) return picked;
    final options = _organizerOptions;
    final byProfile = organizerTypeFromWire(_profile?.defaultOrganizer);
    if (byProfile != null && options.contains(byProfile)) return byProfile.name;
    return options.isEmpty ? null : options.first.name;
  }

  Object? _valueOf(Question q) => q.key == organizerQuestionKey ? _organizerChoice : _answers[q.key];

  List<WizardStep> get _steps => [?_organizerStep, ...(_profile?.steps ?? const <WizardStep>[])];
  int get _totalSteps => 1 + _extraSteps + _steps.length;
  bool get _isLast => _type != null && _step == _totalSteps - 1;

  List<Question> _visible(WizardStep step) => step.questions.where((q) => q.visibleFor(_answers)).toList();

  bool _isBlank(Object? v) => v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);

  String? _errorFor(Question q, {bool force = false}) {
    if (!_showErrors && !force) return null;
    final v = _valueOf(q);
    if (q.required && _isBlank(v)) return 'This one is needed.';
    if (q.kind == QuestionKind.budget && !_isBlank(v) && (v is! double || v <= 0)) {
      return 'Enter a budget greater than zero.';
    }
    final min = _answers[budgetMinKey];
    if (q.kind == QuestionKind.budget && min is double && v is double && min > v) {
      return 'The minimum can\'t be more than the maximum.';
    }
    if (q.kind == QuestionKind.number && !_isBlank(v) && (v is! int || v <= 0)) {
      return 'Enter a number greater than zero.';
    }
    return null;
  }

  bool _stepValid() {
    if (_step == 0) return _type != null;
    if (_onDescribeStep) return _description.trim().length >= 5;
    return _visible(_currentStep).every((q) => _errorFor(q, force: true) == null);
  }

  void _pickType(EventType t) {
    setState(() {
      if (_type != t) {
        _answers.clear();
        _generated = null;
        _generatedFor = null;
        _generateError = null;
      }
      _type = t;
      _error = null;
    });
    _saveDraft();
  }

  Future<void> _next() async {
    if (!_stepValid()) {
      setState(() => _showErrors = true);
      return;
    }
    if (_onDescribeStep && !await _generate()) return;
    if (!_isLast) {
      setState(() {
        _step++;
        _showErrors = false;
        _error = null;
      });
      _saveDraft();
      return;
    }
    await _submit();
  }

  /// Writes the questions for the typed description. Returns false (and says why) if it failed.
  Future<bool> _generate() async {
    final description = _description.trim();
    if (_generated != null && _generatedFor == description) return true;
    setState(() {
      _generating = true;
      _generateError = null;
    });
    try {
      final generated = await widget.onGenerate!(description);
      if (!mounted) return false;
      setState(() {
        _generated = generated;
        _generatedFor = description;
        _answers.clear(); // answers belonged to the old questions
        _generating = false;
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _generating = false;
        _generateError = 'Could not prepare your questions. Check your connection and try again.';
      });
      return false;
    }
  }

  void _skipDescribe() {
    setState(() {
      _generated = null;
      _generatedFor = _description.trim();
      _generateError = null;
      _answers.clear();
      _step++;
    });
    _saveDraft();
  }

  void _back() {
    if (_step == 0) return widget.onBack?.call();
    setState(() {
      _step--;
      _showErrors = false;
      _error = null;
    });
    _saveDraft();
  }

  Future<void> _submit() async {
    final result = _buildResult();
    if (result == null) {
      setState(() => _error = 'Something is missing. Go back and check your answers.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.onSubmit(result);
    if (error == null) widget.onDraftChanged?.call(null);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  WizardResult? _buildResult() {
    final core = <String, Object?>{};
    final details = <String, dynamic>{};
    for (final step in _steps) {
      for (final q in _visible(step)) {
        final v = _valueOf(q);
        if (_isBlank(v)) continue;
        if (q.mapsTo != null) {
          core[q.mapsTo!] = v;
        } else {
          details[q.key] = v;
        }
      }
    }
    if (_location != null) details['location'] = _location!.toJson();
    final name = core['name'], region = core['region'], date = core['primaryDate'];
    final guests = core['guestCountEstimate'], budget = core['totalBudget'];
    var tier = core['budgetTier'];
    final min = _answers[budgetMinKey];
    if (min is double && budget is double && min < budget) details['budgetMin'] = min;
    if (tier == customTierValue && guests is int && budget is double) {
      tier = enumWireValue(tierForPerGuest(budget / guests));
    }
    if (_type == null ||
        name is! String ||
        region is! String ||
        date is! DateTime ||
        guests is! int ||
        budget is! double ||
        tier is! String) {
      return null;
    }
    return WizardResult(
      type: _type!,
      name: name.trim(),
      region: region.trim(),
      religionOrTradition: core['religionOrTradition'] as String?,
      date: date,
      guests: guests,
      budget: budget,
      tier: BudgetTier.values.firstWhere((t) => enumWireValue(t) == tier),
      details: details,
      generatedProfileId: _type == EventType.custom ? _generated?.profileId : null,
      organizerType: organizerTypeFromWire(core[organizerQuestionKey] as String?),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New event'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _submitting || _generating ? null : _back,
        ),
      ),
      body: SafeArea(
        child: _submitting
            ? _BuildingView(type: _type!, answers: _answers)
            : Column(
                children: [
                  _Progress(current: _step, total: _totalSteps),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      child: SingleChildScrollView(
                        key: ValueKey('step-$_step'),
                        padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.l, AppSpace.xl, AppSpace.xl),
                        child: _step == 0
                            ? _typeStep(text)
                            : _onDescribeStep
                                ? _describeStep(text)
                                : _profileStep(text, _currentStep),
                      ),
                    ),
                  ),
                  BottomActionBar(
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.s),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(color: AppColors.errorText),
                            ),
                          ),
                        ),
                      PrimaryButton(
                        label: _isLast ? 'Create event' : 'Next',
                        loading: _generating,
                        onPressed: _type == null ? null : _next,
                      ),
                      if (_onDescribeStep && !_generating)
                        TextButton(onPressed: _skipDescribe, child: const Text('Skip, use basic questions')),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _typeStep(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What is the event?', style: text.headlineSmall),
        const SizedBox(height: AppSpace.xs),
        Text('Tap the one that fits. We will ask only what matters for it.', style: text.bodyMedium),
        const SizedBox(height: AppSpace.xl),
        for (final t in EventType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.m),
            child: _ChoiceCard(
              icon: _typeIcons[t]!,
              label: eventTypeLabel(t),
              hint: _typeHints[t],
              selected: _type == t,
              onTap: () => _pickType(t),
            ),
          ),
      ],
    );
  }

  Widget _describeStep(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tell us about your event', style: text.headlineSmall),
        const SizedBox(height: AppSpace.xs),
        Text('One line is enough. We will ask the right questions for it.', style: text.bodyMedium),
        const SizedBox(height: AppSpace.xl),
        TextFormField(
          initialValue: _description,
          enabled: !_generating,
          maxLines: 3,
          maxLength: 300,
          decoration: const InputDecoration(hintText: 'e.g. A college tech fest for 500 students'),
          onChanged: (v) {
            setState(() => _description = v);
            _saveDraft();
          },
        ),
        if (_showErrors && _description.trim().length < 5)
          Text('Describe it in a few words.', style: text.bodySmall?.copyWith(color: AppColors.errorText)),
        if (_generating) ...[
          const SizedBox(height: AppSpace.l),
          Text('Designing the right questions for your event…', style: text.bodyMedium),
        ],
        if (_generateError != null) ...[
          const SizedBox(height: AppSpace.l),
          Semantics(
            liveRegion: true,
            child: Text(_generateError!, style: text.bodyMedium?.copyWith(color: AppColors.errorText)),
          ),
        ],
      ],
    );
  }

  Widget _profileStep(TextTheme text, WizardStep step) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(step.title, style: text.headlineSmall),
        if (step.subtitle != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(step.subtitle!, style: text.bodyMedium),
        ],
        const SizedBox(height: AppSpace.xl),
        for (final q in _visible(step))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.l),
            child: QuestionField(
              key: ValueKey('${_type?.name}-${q.key}'),
              question: q,
              value: _valueOf(q),
              errorText: _errorFor(q),
              today: widget.today,
              onLocationPicked: (l) => _location = l,
              minValue: _answers[budgetMinKey] as double?,
              onMinChanged: (v) => setState(() {
                if (v == null) {
                  _answers.remove(budgetMinKey);
                } else {
                  _answers[budgetMinKey] = v;
                }
                _saveDraft();
              }),
              onChanged: (v) => setState(() {
                if (_isBlank(v)) {
                  _answers.remove(q.key);
                } else {
                  _answers[q.key] = v;
                }
                _saveDraft();
              }),
            ),
          ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    // Before a type is chosen the real step count is unknown, so show a small start.
    final value = (current + 1) / (total < 2 ? 5 : total);
    return Semantics(
      label: 'Step ${current + 1} of ${total < 2 ? 'several' : total}',
      child: LinearProgressIndicator(value: value.clamp(0.05, 1.0), minHeight: 4),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.icon, required this.label, this.hint, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.l),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.l),
            border: Border.all(color: selected ? scheme.primary : AppColors.outline, width: selected ? 2 : 1),
            color: selected ? scheme.primary.withValues(alpha: 0.06) : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? scheme.primary : null),
              const SizedBox(width: AppSpace.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
                    if (hint != null)
                      Text(hint!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted)),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders one [Question] by its kind. Values: text -> String, number -> int,
/// budget -> double, date -> DateTime, single select -> String, multi select -> a list of strings.
class QuestionField extends StatefulWidget {
  const QuestionField({
    super.key,
    required this.question,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.today,
    this.onLocationPicked,
    this.minValue,
    this.onMinChanged,
  });

  /// Lower end of a custom budget range (budget questions only).
  final double? minValue;
  final ValueChanged<double?>? onMinChanged;

  /// Called when a place is chosen on the map (location questions only).
  final ValueChanged<PickedLocation>? onLocationPicked;

  final Question question;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final String? errorText;
  final DateTime? today;

  @override
  State<QuestionField> createState() => _QuestionFieldState();
}

class _QuestionFieldState extends State<QuestionField> {
  late final TextEditingController _controller = TextEditingController(text: _initialText());
  bool _otherOpen = false;
  late bool _rangeOpen = widget.minValue != null;
  late final TextEditingController _minController =
      TextEditingController(text: widget.minValue?.round().toString() ?? '');

  Question get _q => widget.question;

  static const _guestShortcuts = [25, 50, 100, 200, 500];
  static const _budgetShortcuts = [
    ('₹1L', 100000.0),
    ('₹2.5L', 250000.0),
    ('₹5L', 500000.0),
    ('₹10L', 1000000.0),
    ('₹25L', 2500000.0),
  ];
  static const _dateShortcuts = [('In 1 month', 1), ('In 3 months', 3), ('In 6 months', 6), ('Next year', 12)];

  int _stepFrom(int n, int dir) => (n + dir * (n >= 10 || (dir > 0 && n >= 5) ? 10 : 1)).clamp(1, 100000);

  /// Sets the box text and reports the typed value, as if the user had entered it.
  void _fill(String shown, Object value) {
    setState(() => _controller.text = shown);
    widget.onChanged(value);
  }

  Widget _organizerCards() {
    final selected = widget.value as String?;
    return Column(
      children: [
        for (final o in _q.options)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.m),
            child: _ChoiceCard(
              icon: organizerTypeInfo[organizerTypeFromWire(o.value)]!.icon,
              label: o.label,
              hint: organizerTypeInfo[organizerTypeFromWire(o.value)]!.purpose,
              selected: selected == o.value,
              onTap: () => widget.onChanged(o.value),
            ),
          ),
      ],
    );
  }

  Widget _chips(List<_Shortcut> items) => Wrap(
        spacing: AppSpace.s,
        runSpacing: AppSpace.s,
        children: [
          for (final i in items)
            ChoiceChip(
              label: Text(i.label),
              selected: i.selected,
              showCheckmark: false,
              onSelected: (_) => i.onTap(),
            ),
        ],
      );

  String _initialText() {
    final v = widget.value;
    if (v is double) return v.round().toString();
    if (v is int || v is String) return v.toString();
    return '';
  }

  @override
  void dispose() {
    _controller.dispose();
    _minController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dateOnly(widget.today ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value as DateTime? ?? today.add(const Duration(days: 30)),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5),
    );
    if (picked != null) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (_q.key == organizerQuestionKey) return _organizerCards();
    switch (_q.kind) {
      case QuestionKind.location:
        return LocationField(
          label: _q.label,
          controller: _controller,
          errorText: widget.errorText,
          onChanged: widget.onChanged,
          onPicked: (l) => widget.onLocationPicked?.call(l),
        );
      case QuestionKind.text:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_q.suggestions.isNotEmpty) ...[
              _chips([
                for (final sug in _q.suggestions)
                  _Shortcut(sug, _controller.text.trim() == sug, () => _fill(sug, sug)),
              ]),
              const SizedBox(height: AppSpace.m),
            ],
            AppTextField(
              label: _q.label,
              controller: _controller,
              errorText: widget.errorText,
              textInputAction: TextInputAction.next,
              onChanged: (s) {
                setState(() {});
                widget.onChanged(s);
              },
            ),
          ],
        );
      case QuestionKind.number:
        final n = int.tryParse(_controller.text.trim());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _chips([
              for (final g in _guestShortcuts) _Shortcut('$g', n == g, () => _fill('$g', g)),
            ]),
            const SizedBox(height: AppSpace.m),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    label: _q.label,
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    errorText: widget.errorText,
                    onChanged: (s) {
                      setState(() {});
                      widget.onChanged(int.tryParse(s.trim()));
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Fewer',
                  onPressed: (n ?? 0) > 1 ? () => _fill('${_stepFrom(n!, -1)}', _stepFrom(n, -1)) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  tooltip: 'More',
                  onPressed: () => _fill('${_stepFrom(n ?? 0, 1)}', _stepFrom(n ?? 0, 1)),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        );
      case QuestionKind.budget:
        final v = widget.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _chips([
              for (final b in _budgetShortcuts)
                _Shortcut(b.$1, v is double && v == b.$2, () => _fill('${b.$2.round()}', b.$2)),
              _Shortcut('Custom range', _rangeOpen, () {
                setState(() => _rangeOpen = !_rangeOpen);
                if (!_rangeOpen) {
                  _minController.clear();
                  widget.onMinChanged?.call(null);
                }
              }),
            ]),
            const SizedBox(height: AppSpace.m),
            if (_rangeOpen) ...[
              AppTextField(
                label: 'Minimum',
                controller: _minController,
                keyboardType: TextInputType.number,
                prefix: const Padding(
                  padding: EdgeInsets.only(left: AppSpace.l, right: AppSpace.s),
                  child: Text('₹'),
                ),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
                helperText: widget.minValue != null ? formatInr(widget.minValue!) : null,
                onChanged: (s) => widget.onMinChanged?.call(parseAmount(s)),
              ),
              const SizedBox(height: AppSpace.m),
            ],
            AppTextField(
              label: _rangeOpen ? 'Maximum' : _q.label,
              controller: _controller,
              keyboardType: TextInputType.number,
              prefix: const Padding(
                padding: EdgeInsets.only(left: AppSpace.l, right: AppSpace.s),
                child: Text('₹'),
              ),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
              errorText: widget.errorText,
              helperText: v is double ? formatInr(v) : null,
              onChanged: (s) => widget.onChanged(parseAmount(s)),
            ),
          ],
        );
      case QuestionKind.date:
        final d = widget.value as DateTime?;
        final today = dateOnly(widget.today ?? DateTime.now());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_q.label, style: text.titleSmall),
            const SizedBox(height: AppSpace.s),
            _chips([
              for (final o in _dateShortcuts)
                () {
                  final date = DateTime(today.year, today.month + o.$2, today.day);
                  return _Shortcut(o.$1, d == date, () => widget.onChanged(date));
                }(),
            ]),
            const SizedBox(height: AppSpace.s),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(d == null ? 'Or choose a date' : formatLongDate(d)),
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
            ),
            _error(text),
          ],
        );
      case QuestionKind.singleSelect:
        final selected = widget.value as String?;
        final knownValues = _q.options.map((o) => o.value).toSet();
        final isOther = selected != null && !knownValues.contains(selected);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_q.label, style: text.titleSmall),
            const SizedBox(height: AppSpace.s),
            Wrap(
              spacing: AppSpace.s,
              runSpacing: AppSpace.s,
              children: [
                for (final o in _q.options)
                  ChoiceChip(
                    label: Text(o.label),
                    selected: selected == o.value,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() => _otherOpen = false);
                      // Tapping the chosen option again clears an optional answer.
                      widget.onChanged(selected == o.value && !_q.required ? null : o.value);
                    },
                  ),
                if (_q.mapsTo == 'budgetTier')
                  ChoiceChip(
                    label: const Text('Custom'),
                    selected: selected == customTierValue,
                    showCheckmark: false,
                    onSelected: (_) => widget.onChanged(customTierValue),
                  ),
                if (_q.allowOther)
                  ChoiceChip(
                    label: const Text('Other'),
                    selected: _otherOpen || isOther,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() => _otherOpen = true);
                      if (!isOther) widget.onChanged(null);
                    },
                  ),
              ],
            ),
            if (_q.allowOther && (_otherOpen || isOther)) ...[
              const SizedBox(height: AppSpace.s),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: 'Type it here'),
                onChanged: widget.onChanged,
              ),
            ],
            _error(text),
          ],
        );
      case QuestionKind.multiSelect:
      case QuestionKind.chips:
        final selected = ((widget.value as List?) ?? const []).cast<String>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_q.label, style: text.titleSmall),
            const SizedBox(height: AppSpace.s),
            Wrap(
              spacing: AppSpace.s,
              runSpacing: AppSpace.s,
              children: [
                for (final o in _q.options)
                  FilterChip(
                    label: Text(o.label),
                    selected: selected.contains(o.value),
                    showCheckmark: false,
                    onSelected: (on) => widget.onChanged([
                      for (final v in selected)
                        if (v != o.value) v,
                      if (on) o.value,
                    ]),
                  ),
              ],
            ),
            _error(text),
          ],
        );
    }
  }

  Widget _error(TextTheme text) => widget.errorText == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text(widget.errorText!, style: text.bodySmall?.copyWith(color: AppColors.errorText)),
        );
}

/// Shown while the server builds the budget (an LLM call, up to a minute and a half).
/// Echoes the user's answers so the wait feels like progress on their event.
class _BuildingView extends StatelessWidget {
  const _BuildingView({required this.type, required this.answers});

  final EventType type;
  final Map<String, Object?> answers;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = answers['name'];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 72),
            const SizedBox(height: AppSpace.xl),
            Text(
              name is String && name.isNotEmpty
                  ? 'Setting up "$name"'
                  : 'Setting up your ${eventTypeLabel(type).toLowerCase()}',
              textAlign: TextAlign.center,
              style: text.titleLarge,
            ),
            const SizedBox(height: AppSpace.s),
            Text(
              'Building a budget that fits your event. This can take up to a minute.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppSpace.xl),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.selected, this.onTap);
  final String label;
  final bool selected;
  final VoidCallback onTap;
}
