import 'package:flutter/material.dart';

import '../../models/enums.dart';

/// What each way of organizing means, shown in the wizard and the team sheet.
class OrganizerTypeInfo {
  const OrganizerTypeInfo(this.icon, this.title, this.purpose);
  final IconData icon;
  final String title;
  final String purpose;
}

const organizerTypeInfo = {
  OrganizerType.individual: OrganizerTypeInfo(
    Icons.person_outline,
    'Just me',
    'You plan on your own. No team, the simplest view.',
  ),
  OrganizerType.family: OrganizerTypeInfo(
    Icons.family_restroom_outlined,
    'Family',
    'Relatives plan together on trust. Anyone you invite joins at once and can edit.',
  ),
  OrganizerType.committee: OrganizerTypeInfo(
    Icons.groups_outlined,
    'Committee',
    'A group with roles. Members propose, the treasurer approves spending.',
  ),
  OrganizerType.company: OrganizerTypeInfo(
    Icons.business_outlined,
    'Company',
    'You lead. Staff join with your approval and only you or approvers change the budget.',
  ),
};

/// The question key the wizard uses for the organizer step.
const organizerQuestionKey = 'organizerType';

OrganizerType? organizerTypeFromWire(String? wire) {
  for (final t in OrganizerType.values) {
    if (t.name == wire) return t;
  }
  return null;
}
