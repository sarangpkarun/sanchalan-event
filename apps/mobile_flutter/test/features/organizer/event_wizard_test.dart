import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setzo/features/organizer/event_wizard_view.dart';
import 'package:setzo/models/enums.dart';
import 'package:setzo/features/organizer/event_draft.dart';
import 'package:setzo/models/event_profile.dart';

Map<String, dynamic> _q(String key, String label, String kind,
        {String? mapsTo, bool required = false, List<List<String>>? options, Map<String, String>? showIf}) =>
    {
      'key': key,
      'label': label,
      'kind': kind,
      'required': required,
      'mapsTo': ?mapsTo,
      'showIf': ?showIf,
      if (options != null) 'options': [for (final o in options) {'value': o[0], 'label': o[1]}],
    };

final _profiles = [
  EventTypeProfile.fromJson({
    'eventType': 'birthday',
    'organizerOptions': ['family'],
    'version': 1,
    'steps': [
      {
        'id': 'basics',
        'title': 'Let us start',
        'questions': [_q('name', 'Party name', 'text', mapsTo: 'name', required: true)],
      },
      {
        'id': 'style',
        'title': 'The fun part',
        'questions': [
          _q('region', 'City', 'text', mapsTo: 'region', required: true),
          _q('theme', 'Theme', 'text'),
          _q('food', 'Food', 'single_select', options: [
            ['veg', 'Vegetarian'],
            ['both', 'Both'],
          ]),
          _q('guestNote', 'Veg guests', 'text', showIf: {'key': 'food', 'equals': 'veg'}),
        ],
      },
      {
        'id': 'budget',
        'title': 'Numbers',
        'questions': [
          _q('guestCountEstimate', 'Guests', 'number', mapsTo: 'guestCountEstimate', required: true),
          _q('totalBudget', 'Budget', 'budget', mapsTo: 'totalBudget', required: true),
          _q('budgetTier', 'Style', 'single_select',
              mapsTo: 'budgetTier', required: true, options: [
                ['standard', 'Standard'],
              ]),
          _q('primaryDate', 'Date', 'date', mapsTo: 'primaryDate', required: true),
        ],
      },
    ],
  }),
];

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  customTests();
  shortcutTests();
  organizerTests();
  testWidgets('walks the steps, asks only the type questions, and submits the split result', (t) async {
    WizardResult? got;
    await t.pumpWidget(MaterialApp(
      home: EventWizardView(
        profiles: _profiles,
        today: DateTime(2026, 10, 13),
        onSubmit: (r) async {
          got = r;
          return null;
        },
      ),
    ));

    // Next is disabled until a type is chosen; wedding has no profile here, so it uses none.
    await _tap(t, find.text('Birthday'));
    await _tap(t, find.text('Next'));

    // Required name blocks the step.
    await _tap(t, find.text('Next'));
    expect(find.text('This one is needed.'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Aarav turns 5');
    await _tap(t, find.text('Next'));

    // showIf: the follow-up appears only after choosing Vegetarian.
    expect(find.text('Veg guests'), findsNothing);
    await _tap(t, find.text('Vegetarian'));
    expect(find.text('Veg guests'), findsOneWidget);
    await t.enterText(find.byType(TextField).at(0), 'Pune');
    await t.enterText(find.byType(TextField).at(1), 'Dinosaurs');
    await _tap(t, find.text('Next'));

    await t.enterText(find.byType(TextField).at(0), '40');
    await t.enterText(find.byType(TextField).at(1), '50,000');
    await _tap(t, find.text('Standard'));
    await _tap(t, find.text('Or choose a date'));
    await _tap(t, find.text('OK'));
    await _tap(t, find.text('Create event'));

    expect(got, isNotNull);
    expect(got!.type, EventType.birthday);
    expect(got!.name, 'Aarav turns 5');
    expect(got!.region, 'Pune');
    expect(got!.guests, 40);
    expect(got!.budget, 50000);
    expect(got!.tier, BudgetTier.standard);
    // Only type-specific answers go into details, not the core fields.
    expect(got!.details, {'theme': 'Dinosaurs', 'food': 'veg'});
  });

  testWidgets('custom range and Custom style: min goes to details, tier matches per-guest spend', (t) async {
    WizardResult? got;
    await t.pumpWidget(MaterialApp(
      home: EventWizardView(
        profiles: _profiles,
        today: DateTime(2026, 10, 13),
        onSubmit: (r) async {
          got = r;
          return null;
        },
      ),
    ));
    await _tap(t, find.text('Birthday'));
    await _tap(t, find.text('Next'));
    await t.enterText(find.byType(TextField).first, 'Party');
    await _tap(t, find.text('Next'));
    await t.enterText(find.byType(TextField).at(0), 'Pune');
    await _tap(t, find.text('Next'));

    await t.enterText(find.byType(TextField).at(0), '100');
    await _tap(t, find.text('Custom range'));
    await t.enterText(find.byType(TextField).at(1), '600,000');
    await t.enterText(find.byType(TextField).at(2), '500,000');
    await _tap(t, find.text('Custom'));
    await _tap(t, find.text('Or choose a date'));
    await _tap(t, find.text('OK'));
    await _tap(t, find.text('Create event'));
    expect(got, isNull); // minimum above maximum is rejected
    expect(find.text("The minimum can't be more than the maximum."), findsOneWidget);

    await t.enterText(find.byType(TextField).at(1), '300,000');
    await _tap(t, find.text('Create event'));
    expect(got, isNotNull);
    expect(got!.budget, 500000);
    expect(got!.details['budgetMin'], 300000);
    expect(got!.tier, BudgetTier.standard); // 5,000 per guest
  });
}

// --- custom events: the server writes the questions ---

EventTypeProfile _custom(List<Map<String, dynamic>> middle) => EventTypeProfile.fromJson({
      'eventType': 'custom',
      'organizerOptions': ['family'],
      'version': 1,
      'steps': [
        {
          'id': 'basics',
          'title': 'Basics',
          'questions': [_q('name', 'Event name', 'text', mapsTo: 'name', required: true)],
        },
        ...middle,
      ],
    });

void organizerTests() {
  EventTypeProfile profile(String type, List<String> options, String? def) => EventTypeProfile.fromJson({
        'eventType': type,
        'version': 2,
        'organizerOptions': options,
        'defaultOrganizer': ?def,
        'steps': [
          {
            'id': 'basics',
            'title': 'Basics',
            'questions': [_q('name', 'Event name', 'text', mapsTo: 'name', required: true)],
          },
          {
            'id': 'core',
            'title': 'Core',
            'questions': [
              _q('region', 'Where?', 'text', mapsTo: 'region', required: true),
              _q('guestCountEstimate', 'Guests', 'number', mapsTo: 'guestCountEstimate', required: true),
              _q('totalBudget', 'Budget', 'budget', mapsTo: 'totalBudget', required: true),
              _q('budgetTier', 'Style', 'single_select', mapsTo: 'budgetTier', required: true, options: [
                ['standard', 'Standard'],
              ]),
              _q('primaryDate', 'Date', 'date', mapsTo: 'primaryDate', required: true),
            ],
          },
        ],
      });

  testWidgets('who is organizing: only the kinds the event type allows, with its default pre-selected', (t) async {
    WizardResult? got;
    await t.pumpWidget(MaterialApp(
      home: EventWizardView(
        profiles: [profile('corporate', ['company', 'committee'], 'company')],
        today: DateTime(2026, 10, 13),
        onSubmit: (r) async {
          got = r;
          return null;
        },
      ),
    ));
    await _tap(t, find.text('Corporate'));
    await _tap(t, find.text('Next'));
    expect(find.text('Who is organizing?'), findsWidgets);
    expect(find.text('Company'), findsOneWidget);
    expect(find.text('Committee'), findsOneWidget);
    expect(find.text('Family'), findsNothing);
    expect(find.text('Just me'), findsNothing);

    await _tap(t, find.text('Committee'));
    await _tap(t, find.text('Next'));
    await t.enterText(find.byType(TextField), 'Annual day');
    await _tap(t, find.text('Next'));
    await t.enterText(find.byType(TextField).at(0), 'Pune');
    await t.enterText(find.byType(TextField).at(1), '100');
    await t.enterText(find.byType(TextField).at(2), '50,000');
    await _tap(t, find.text('Standard'));
    await _tap(t, find.text('In 1 month'));
    await _tap(t, find.text('Create event'));

    expect(got!.organizerType, OrganizerType.committee);
    // The organizer answer is a core field, not a type-specific detail.
    expect(got!.details, isEmpty);
  });

  testWidgets('the default organizer is used when the user just continues', (t) async {
    WizardResult? got;
    await t.pumpWidget(MaterialApp(
      home: EventWizardView(
        profiles: [profile('birthday', ['individual', 'family'], 'family')],
        today: DateTime(2026, 10, 13),
        onSubmit: (r) async {
          got = r;
          return null;
        },
      ),
    ));
    await _tap(t, find.text('Birthday'));
    await _tap(t, find.text('Next'));
    await _tap(t, find.text('Next'));
    await t.enterText(find.byType(TextField), 'Aarav');
    await _tap(t, find.text('Next'));
    await t.enterText(find.byType(TextField).at(0), 'Pune');
    await t.enterText(find.byType(TextField).at(1), '40');
    await t.enterText(find.byType(TextField).at(2), '10,000');
    await _tap(t, find.text('Standard'));
    await _tap(t, find.text('In 1 month'));
    await _tap(t, find.text('Create event'));
    expect(got!.organizerType, OrganizerType.family);
  });
}

void shortcutTests() {
  testWidgets('suggestion chips fill a text question; guests, budget and date have shortcuts', (t) async {
    WizardResult? got;
    final profile = EventTypeProfile.fromJson({
      'eventType': 'birthday',
      'organizerOptions': ['family'],
      'version': 2,
      'steps': [
        {
          'id': 'basics',
          'title': 'Start',
          'questions': [
            {..._q('name', 'Whose birthday is it?', 'text', mapsTo: 'name', required: true), 'suggestions': ['My birthday', 'A friend\'s birthday']},
            _q('region', 'Where?', 'text', mapsTo: 'region', required: true),
          ],
        },
        {
          'id': 'core',
          'title': 'Core',
          'questions': [
            _q('guestCountEstimate', 'Guests', 'number', mapsTo: 'guestCountEstimate', required: true),
            _q('totalBudget', 'Budget', 'budget', mapsTo: 'totalBudget', required: true),
            _q('budgetTier', 'Style', 'single_select', mapsTo: 'budgetTier', required: true, options: [
              ['standard', 'Standard'],
            ]),
            _q('primaryDate', 'Date', 'date', mapsTo: 'primaryDate', required: true),
          ],
        },
      ],
    });
    await t.pumpWidget(MaterialApp(
      home: EventWizardView(
        profiles: [profile],
        today: DateTime(2026, 10, 13),
        onSubmit: (r) async {
          got = r;
          return null;
        },
      ),
    ));
    await _tap(t, find.text('Birthday'));
    await _tap(t, find.text('Next'));
    await _tap(t, find.text('My birthday'));
    expect(find.widgetWithText(TextField, 'My birthday'), findsOneWidget);
    await t.enterText(find.byType(TextField).at(1), 'Pune');
    await _tap(t, find.text('Next'));

    await _tap(t, find.text('100'));
    await _tap(t, find.byTooltip('More'));
    await _tap(t, find.text('₹5L'));
    await _tap(t, find.text('Standard'));
    await _tap(t, find.text('In 3 months'));
    await _tap(t, find.text('Create event'));

    expect(got!.name, 'My birthday');
    expect(got!.guests, 110);
    expect(got!.budget, 500000);
    expect(got!.date, DateTime(2027, 1, 13));
  });
}

void customTests() {
  final generic = _custom([]);
  final written = _custom([
    {
      'id': 'gen1',
      'title': 'About the crowd',
      'questions': [_q('chiefGuest', 'Who is the chief guest?', 'text')],
    },
  ]);

  Widget app({
    required Future<GeneratedProfile> Function(String) onGenerate,
    List<String>? calls,
    WizardDraft? draft,
  }) =>
      MaterialApp(
        home: EventWizardView(
          profiles: [generic],
          draft: draft,
          onGenerate: (d) {
            calls?.add(d);
            return onGenerate(d);
          },
          onSubmit: (_) async => null,
        ),
      );

  testWidgets('custom: describe, then the written questions replace the basic ones', (t) async {
    final calls = <String>[];
    await t.pumpWidget(app(
      calls: calls,
      onGenerate: (_) async => GeneratedProfile(profileId: 'p1', profile: written),
    ));
    await _tap(t, find.text('Custom'));
    await _tap(t, find.text('Next'));

    // The describe step needs a few words before it moves on.
    expect(find.text('Tell us about your event'), findsOneWidget);
    await _tap(t, find.text('Next'));
    expect(calls, isEmpty);
    await t.enterText(find.byType(TextField), 'A college tech fest');
    await _tap(t, find.text('Next'));
    expect(calls, ['A college tech fest']);

    // Basics step, then the written step.
    await t.enterText(find.byType(TextField), 'TechFest');
    await _tap(t, find.text('Next'));
    expect(find.text('Who is the chief guest?'), findsOneWidget);

    // Going back and continuing without edits does not call the server again.
    await _tap(t, find.byTooltip('Back'));
    await _tap(t, find.byTooltip('Back'));
    await _tap(t, find.text('Next'));
    expect(calls, hasLength(1));
  });

  testWidgets('custom: a failure keeps the user on the describe step; skip uses the basic questions', (t) async {
    await t.pumpWidget(app(onGenerate: (_) async => throw Exception('offline')));
    await _tap(t, find.text('Custom'));
    await _tap(t, find.text('Next'));
    await t.enterText(find.byType(TextField), 'A college tech fest');
    await _tap(t, find.text('Next'));
    expect(find.textContaining('Could not prepare your questions'), findsOneWidget);
    expect(find.text('Tell us about your event'), findsOneWidget);

    await _tap(t, find.text('Skip, use basic questions'));
    expect(find.text('Basics'), findsOneWidget);
  });
}
