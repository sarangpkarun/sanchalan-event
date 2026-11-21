import 'package:json_annotation/json_annotation.dart';

import 'converters.dart';
import 'enums.dart';
import 'roadmap.dart';

part 'event.g.dart';

@JsonSerializable()
class SubEvent {
  const SubEvent({
    required this.id,
    required this.eventGroupId,
    required this.name,
    this.subEventType,
    required this.date,
    this.startTime,
    this.endTime,
    this.venueName,
    this.venueAddress,
    this.expectedGuestCount,
    required this.status,
  });
  factory SubEvent.fromJson(Map<String, dynamic> json) => _$SubEventFromJson(json);
  final String id;
  final String eventGroupId;
  final String name;
  final String? subEventType;
  final DateTime date;
  final String? startTime;
  final String? endTime;
  final String? venueName;
  final String? venueAddress;
  final int? expectedGuestCount;
  final SubEventStatus status;
  Map<String, dynamic> toJson() => _$SubEventToJson(this);
}

@JsonSerializable()
class BudgetCategory {
  const BudgetCategory({
    required this.id,
    required this.eventGroupId,
    required this.categoryKey,
    required this.allocatedAmount,
    this.budgetTierOverride,
  });
  factory BudgetCategory.fromJson(Map<String, dynamic> json) => _$BudgetCategoryFromJson(json);
  final String id;
  final String eventGroupId;
  final String categoryKey;
  @MoneyConverter()
  final double allocatedAmount;
  final BudgetTier? budgetTierOverride;
  Map<String, dynamic> toJson() => _$BudgetCategoryToJson(this);
}

/// An event group as returned by GET /event-groups/me (sub-events included,
/// budget categories and tasks absent). Also the base of the detail response.
@JsonSerializable(explicitToJson: true)
class EventGroup {
  const EventGroup({
    required this.id,
    required this.organizerId,
    this.organizerType = OrganizerType.individual,
    required this.eventType,
    required this.name,
    required this.region,
    this.religionOrTradition,
    required this.totalBudget,
    required this.budgetTier,
    required this.guestCountEstimate,
    required this.primaryDate,
    required this.status,
    required this.createdAt,
    required this.subEvents,
    required this.budgetCategories,
    required this.tasks,
    this.myRole,
    this.details,
  });
  factory EventGroup.fromJson(Map<String, dynamic> json) => _$EventGroupFromJson(json);
  final String id;
  final String organizerId;

  /// Who is organizing this event (decides how the team and approvals work).
  @JsonKey(defaultValue: OrganizerType.individual)
  final OrganizerType organizerType;
  final EventType eventType;
  final String name;
  final String region;
  final String? religionOrTradition;
  @MoneyConverter()
  final double totalBudget;
  final BudgetTier budgetTier;
  final int guestCountEstimate;
  final DateTime primaryDate;
  final EventGroupStatus status;
  final DateTime createdAt;

  /// Answers to the event type's own questions (also holds `budgetMin` for a custom range).
  final Map<String, dynamic>? details;

  /// The signed-in organizer's role on this event: owner, approver, editor or viewer.
  /// Present on list and get responses; null elsewhere (treated as owner).
  final String? myRole;

  /// Present on list, create, get and update responses.
  @JsonKey(defaultValue: <SubEvent>[])
  final List<SubEvent> subEvents;

  /// Present on create and get (not on list).
  @JsonKey(defaultValue: <BudgetCategory>[])
  final List<BudgetCategory> budgetCategories;

  /// Present on get only.
  @JsonKey(defaultValue: <TaskWithDependencies>[])
  final List<TaskWithDependencies> tasks;
  Map<String, dynamic> toJson() => _$EventGroupToJson(this);

  bool get isOwner => myRole == null || myRole == 'owner';
  bool get canEdit => myRole != 'viewer';
}

@JsonSerializable(includeIfNull: false)
class CreateEventGroupBody {
  const CreateEventGroupBody({
    this.organizerType,
    required this.eventType,
    required this.name,
    required this.region,
    this.religionOrTradition,
    this.details,
    this.generatedProfileId,
    required this.totalBudget,
    required this.budgetTier,
    required this.guestCountEstimate,
    required this.primaryDate,
  });
  factory CreateEventGroupBody.fromJson(Map<String, dynamic> json) =>
      _$CreateEventGroupBodyFromJson(json);
  final OrganizerType? organizerType;
  final EventType eventType;
  final String name;
  final String region;
  final String? religionOrTradition;

  /// Type-specific wizard answers (community, theme, venue style, ...).
  final Map<String, dynamic>? details;

  /// Set when a custom event used LLM-written questions.
  final String? generatedProfileId;
  final double totalBudget;
  final BudgetTier budgetTier;
  final int guestCountEstimate;

  /// YYYY-MM-DD (use [toDateOnly]).
  final String primaryDate;
  Map<String, dynamic> toJson() => _$CreateEventGroupBodyToJson(this);
}

@JsonSerializable(includeIfNull: false)
class UpdateEventGroupBody {
  const UpdateEventGroupBody({
    this.name,
    this.totalBudget,
    this.budgetTier,
    this.guestCountEstimate,
    this.primaryDate,
    this.budgetAdjustment,
    this.budgetMin,
    this.clearBudgetMin = false,
  });
  factory UpdateEventGroupBody.fromJson(Map<String, dynamic> json) =>
      _$UpdateEventGroupBodyFromJson(json);
  final String? name;
  final double? totalBudget;
  final BudgetTier? budgetTier;
  final int? guestCountEstimate;
  final String? primaryDate;

  /// Only used when [totalBudget] changes.
  final BudgetAdjustment? budgetAdjustment;

  /// Lower end of a custom budget range.
  final double? budgetMin;

  /// Removes a previously saved range (sends `budgetMin: null`).
  @JsonKey(includeToJson: false, includeFromJson: false)
  final bool clearBudgetMin;
  Map<String, dynamic> toJson() => {
        ..._$UpdateEventGroupBodyToJson(this),
        if (clearBudgetMin) 'budgetMin': null,
      };
}

@JsonSerializable(explicitToJson: true)
class UpdateEventGroupResponse {
  const UpdateEventGroupResponse({
    required this.eventGroup,
    required this.budgetCategories,
    this.warning,
  });
  factory UpdateEventGroupResponse.fromJson(Map<String, dynamic> json) =>
      _$UpdateEventGroupResponseFromJson(json);
  final EventGroup eventGroup;
  final List<BudgetCategory> budgetCategories;
  final String? warning;
  Map<String, dynamic> toJson() => _$UpdateEventGroupResponseToJson(this);
}

@JsonSerializable(includeIfNull: false)
class CreateBudgetCategoryBody {
  const CreateBudgetCategoryBody({required this.categoryKey, required this.allocatedAmount});
  factory CreateBudgetCategoryBody.fromJson(Map<String, dynamic> json) =>
      _$CreateBudgetCategoryBodyFromJson(json);
  final String categoryKey;
  final double allocatedAmount;
  Map<String, dynamic> toJson() => _$CreateBudgetCategoryBodyToJson(this);
}

@JsonSerializable(includeIfNull: false)
class UpdateBudgetCategoryBody {
  const UpdateBudgetCategoryBody({this.allocatedAmount, this.budgetTierOverride, this.categoryKey});
  factory UpdateBudgetCategoryBody.fromJson(Map<String, dynamic> json) =>
      _$UpdateBudgetCategoryBodyFromJson(json);
  final double? allocatedAmount;
  final BudgetTier? budgetTierOverride;

  /// Rename.
  final String? categoryKey;
  Map<String, dynamic> toJson() => _$UpdateBudgetCategoryBodyToJson(this);
}

/// Response of POST/PATCH /event-groups/:id/budget-categories[/:categoryId].
@JsonSerializable(explicitToJson: true)
class BudgetCategoryMutationResponse {
  const BudgetCategoryMutationResponse({required this.budgetCategory, this.warning});
  factory BudgetCategoryMutationResponse.fromJson(Map<String, dynamic> json) =>
      _$BudgetCategoryMutationResponseFromJson(json);
  final BudgetCategory budgetCategory;
  final String? warning;
  Map<String, dynamic> toJson() => _$BudgetCategoryMutationResponseToJson(this);
}

@JsonSerializable(explicitToJson: true)
class DeleteBudgetCategoryResponse {
  const DeleteBudgetCategoryResponse({required this.budgetCategories, this.warning});
  factory DeleteBudgetCategoryResponse.fromJson(Map<String, dynamic> json) =>
      _$DeleteBudgetCategoryResponseFromJson(json);
  final List<BudgetCategory> budgetCategories;
  final String? warning;
  Map<String, dynamic> toJson() => _$DeleteBudgetCategoryResponseToJson(this);
}

/// Response of DELETE /event-groups/:id.
@JsonSerializable()
class DeleteEventGroupResponse {
  const DeleteEventGroupResponse({required this.deleted, required this.id});
  factory DeleteEventGroupResponse.fromJson(Map<String, dynamic> json) =>
      _$DeleteEventGroupResponseFromJson(json);
  final bool deleted;
  final String id;
  Map<String, dynamic> toJson() => _$DeleteEventGroupResponseToJson(this);
}
