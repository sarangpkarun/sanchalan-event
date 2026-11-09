// Collaborators on an event (see apps/backend/src/services/event-member.service.ts).
// Hand-written, no codegen.

class EventMember {
  const EventMember({required this.userId, this.name, this.phoneNumber, required this.role, required this.status});
  factory EventMember.fromJson(Map<String, dynamic> j) => EventMember(
        userId: j['userId'] as String,
        name: j['name'] as String?,
        phoneNumber: j['phoneNumber'] as String?,
        role: j['role'] as String,
        status: j['status'] as String,
      );

  final String userId;
  final String? name;

  /// Only sent to the event's owner.
  final String? phoneNumber;
  final String role;
  final String status;

  bool get pending => status == 'pending';
}

class EventInvite {
  const EventInvite({required this.id, required this.code, required this.role, required this.expiresAt, this.requiresApproval = false});
  factory EventInvite.fromJson(Map<String, dynamic> j) => EventInvite(
        id: j['id'] as String,
        code: j['code'] as String,
        role: j['role'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        requiresApproval: j['requiresApproval'] as bool? ?? false,
      );

  final String id;
  final String code;
  final String role;
  final DateTime expiresAt;
  final bool requiresApproval;
}

class EventTeam {
  const EventTeam({required this.myRole, required this.organizerType, required this.members, required this.invites});
  factory EventTeam.fromJson(Map<String, dynamic> j) => EventTeam(
        myRole: j['myRole'] as String,
        organizerType: j['organizerType'] as String?,
        members: (j['members'] as List).map((m) => EventMember.fromJson(m as Map<String, dynamic>)).toList(),
        invites: (j['invites'] as List).map((m) => EventInvite.fromJson(m as Map<String, dynamic>)).toList(),
      );

  final String myRole;
  /// Who is organizing the event: decides how joining and the budget work.
  final String? organizerType;
  final List<EventMember> members;
  final List<EventInvite> invites;

  bool get isOwner => myRole == 'owner';
}

class JoinResult {
  const JoinResult({required this.eventGroupId, required this.eventName, required this.status});
  factory JoinResult.fromJson(Map<String, dynamic> j) => JoinResult(
        eventGroupId: j['eventGroupId'] as String,
        eventName: j['eventName'] as String,
        status: j['status'] as String,
      );

  final String eventGroupId;
  final String eventName;
  final String status;

  bool get pending => status == 'pending';
}

String memberRoleLabel(String role) => switch (role) {
      'owner' => 'Organizer',
      'approver' => 'Approver',
      'editor' => 'Editor',
      'viewer' => 'Viewer',
      _ => role,
    };

String memberRoleHint(String role) => switch (role) {
      'approver' => 'Can edit everything, including the budget',
      'editor' => 'Can edit tasks and the roadmap',
      'viewer' => 'Can only look',
      _ => '',
    };
