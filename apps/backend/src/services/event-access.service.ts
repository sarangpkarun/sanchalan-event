import type { EventGroup, EventGroupRole } from "@prisma/client";
import { prisma } from "../lib/prisma.js";
import { AppError } from "../lib/errors.js";

// Who may do what on an event. The creator (EventGroup.organizerId) is always `owner`.
// Collaborators are RolePermission rows; a `pending` row (waiting for the owner's approval)
// grants nothing.
//
//   owner     everything: delete, invite, approve, change roles, budget
//   approver  edit + the budget authority (in a company event only owner/approver touch budget)
//   editor    edit tasks, roadmap, event details (and the budget outside company events)
//   viewer    read only

export interface EventAccess {
  eventGroup: EventGroup;
  role: EventGroupRole;
  /** The event's creator is a company: the initiator holds the authority. */
  ownerIsCompany: boolean;
}

export async function getEventAccess(organizerId: string, eventGroupId: string): Promise<EventAccess> {
  const eventGroup = await prisma.eventGroup.findUnique({
    where: { id: eventGroupId },
    include: { organizer: { select: { organizerType: true } } },
  });
  if (!eventGroup) throw new AppError(404, "Event not found");
  const { organizer, ...rest } = eventGroup;
  const ownerIsCompany = organizer.organizerType === "company";
  if (rest.organizerId === organizerId) return { eventGroup: rest, role: "owner", ownerIsCompany };

  const member = await prisma.rolePermission.findUnique({
    where: { eventGroupId_userId: { eventGroupId, userId: organizerId } },
  });
  if (!member || member.status !== "active") throw new AppError(403, "Forbidden");
  return { eventGroup: rest, role: member.role, ownerIsCompany };
}

export async function requireRead(organizerId: string, eventGroupId: string): Promise<EventAccess> {
  return getEventAccess(organizerId, eventGroupId);
}

export async function requireEdit(organizerId: string, eventGroupId: string): Promise<EventAccess> {
  const access = await getEventAccess(organizerId, eventGroupId);
  if (access.role === "viewer") throw new AppError(403, "You have view-only access to this event");
  return access;
}

export function canEditBudget(access: EventAccess): boolean {
  if (access.role === "owner" || access.role === "approver") return true;
  return access.role === "editor" && !access.ownerIsCompany;
}

export async function requireBudgetEdit(organizerId: string, eventGroupId: string): Promise<EventAccess> {
  const access = await getEventAccess(organizerId, eventGroupId);
  if (!canEditBudget(access)) {
    throw new AppError(403, "Only the organizer or an approver can change the budget of this event");
  }
  return access;
}

export async function requireOwner(organizerId: string, eventGroupId: string): Promise<EventAccess> {
  const access = await getEventAccess(organizerId, eventGroupId);
  if (access.role !== "owner") throw new AppError(403, "Only the person who created this event can do that");
  return access;
}
