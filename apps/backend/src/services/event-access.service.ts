import type { EventGroup, EventGroupRole, OrganizerType } from "@prisma/client";
import { prisma } from "../lib/prisma.js";
import { AppError } from "../lib/errors.js";

// Who may do what on an event. The creator (EventGroup.organizerId) is always `owner`.
// Collaborators are RolePermission rows; a `pending` row (waiting for the owner's approval)
// grants nothing.
//
//   owner     everything: delete, invite, approve, change roles, budget
//   approver  edit + the budget authority (committee: the treasurer; company: delegated by the initiator)
//   editor    edit tasks, roadmap, event details (family: also the budget; committee: proposes
//             budget changes instead; company: no budget)
//   viewer    read only
//
// How much authority a role carries depends on EventGroup.organizerType (who is organizing).

export interface EventAccess {
  eventGroup: EventGroup;
  role: EventGroupRole;
  /** Who is organizing this event (family, committee, company, individual). */
  organizerType: OrganizerType;
}

export async function getEventAccess(organizerId: string, eventGroupId: string): Promise<EventAccess> {
  const eventGroup = await prisma.eventGroup.findUnique({ where: { id: eventGroupId } });
  if (!eventGroup) throw new AppError(404, "Event not found");
  const { organizerType } = eventGroup;
  if (eventGroup.organizerId === organizerId) return { eventGroup, role: "owner", organizerType };

  const member = await prisma.rolePermission.findUnique({
    where: { eventGroupId_userId: { eventGroupId, userId: organizerId } },
  });
  if (!member || member.status !== "active") throw new AppError(403, "Forbidden");
  return { eventGroup, role: member.role, organizerType };
}

export async function requireRead(organizerId: string, eventGroupId: string): Promise<EventAccess> {
  return getEventAccess(organizerId, eventGroupId);
}

export async function requireEdit(organizerId: string, eventGroupId: string): Promise<EventAccess> {
  const access = await getEventAccess(organizerId, eventGroupId);
  if (access.role === "viewer") throw new AppError(403, "You have view-only access to this event");
  return access;
}

/** Direct budget changes. In a committee, editors send proposals instead (see canProposeBudget). */
export function canEditBudget(access: EventAccess): boolean {
  if (access.role === "owner" || access.role === "approver") return true;
  return access.role === "editor" && access.organizerType !== "company" && access.organizerType !== "committee";
}

/** Committee members who cannot change the budget directly may propose a change. */
export function canProposeBudget(access: EventAccess): boolean {
  return access.organizerType === "committee" && access.role === "editor";
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
