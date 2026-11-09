import crypto from "node:crypto";
import { prisma } from "../lib/prisma.js";
import { AppError } from "../lib/errors.js";
import { getEventAccess, requireOwner } from "./event-access.service.js";
import type { CreateInviteInput, UpdateMemberInput } from "../schemas/event-member.schema.js";

const INVITE_DAYS = 7;
// No 0/O/1/I so a code read aloud or typed from a screenshot is not ambiguous.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function newCode(): string {
  const bytes = crypto.randomBytes(8);
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

export async function createInvite(organizerId: string, eventGroupId: string, input: CreateInviteInput) {
  const { organizerType } = await requireOwner(organizerId, eventGroupId);
  if (organizerType === "individual") {
    throw new AppError(400, "This event is planned on your own. Make it a Family, Committee or Company event to invite people.");
  }
  const invite = await prisma.eventInvite.create({
    data: {
      code: newCode(),
      eventGroupId,
      role: input.role,
      createdBy: organizerId,
      expiresAt: new Date(Date.now() + INVITE_DAYS * 24 * 3600 * 1000),
    },
  });
  return {
    id: invite.id,
    code: invite.code,
    role: invite.role,
    expiresAt: invite.expiresAt,
    // For a company event the initiator approves each person who joins.
    requiresApproval: organizerType === "company",
  };
}

export async function revokeInvite(organizerId: string, eventGroupId: string, inviteId: string) {
  await requireOwner(organizerId, eventGroupId);
  const result = await prisma.eventInvite.updateMany({
    where: { id: inviteId, eventGroupId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
  if (result.count === 0) throw new AppError(404, "Invite not found");
  return { revoked: true };
}

export async function joinByCode(organizerId: string, code: string) {
  const invite = await prisma.eventInvite.findUnique({
    where: { code },
    include: { eventGroup: true },
  });
  if (!invite || invite.revokedAt || invite.expiresAt < new Date()) {
    throw new AppError(404, "This invite code is not valid or has expired");
  }
  const { eventGroup } = invite;
  if (eventGroup.organizerId === organizerId) throw new AppError(400, "This is your own event");

  const existing = await prisma.rolePermission.findUnique({
    where: { eventGroupId_userId: { eventGroupId: eventGroup.id, userId: organizerId } },
  });
  const summary = (status: "active" | "pending") => ({
    eventGroupId: eventGroup.id,
    eventName: eventGroup.name,
    status,
  });
  if (existing) return summary(existing.status);

  const status = eventGroup.organizerType === "company" ? "pending" : "active";
  await prisma.rolePermission.create({
    data: { eventGroupId: eventGroup.id, userId: organizerId, role: invite.role, status, invitedAt: new Date() },
  });
  return summary(status);
}

export async function listMembers(organizerId: string, eventGroupId: string) {
  const access = await getEventAccess(organizerId, eventGroupId);
  const isOwner = access.role === "owner";
  const [owner, rows, invites] = await Promise.all([
    prisma.organizer.findUniqueOrThrow({ where: { id: access.eventGroup.organizerId } }),
    prisma.rolePermission.findMany({
      where: { eventGroupId },
      include: { user: { select: { id: true, displayName: true, phoneNumber: true } } },
      orderBy: { invitedAt: "asc" },
    }),
    isOwner
      ? prisma.eventInvite.findMany({
          where: { eventGroupId, revokedAt: null, expiresAt: { gt: new Date() } },
          orderBy: { createdAt: "desc" },
        })
      : Promise.resolve([]),
  ]);
  return {
    myRole: access.role,
    organizerType: access.organizerType,
    members: [
      { userId: owner.id, name: owner.displayName, role: "owner" as const, status: "active" as const },
      ...rows
        // Pending people are only visible to the owner who has to approve them.
        .filter((r) => isOwner || r.status === "active")
        .map((r) => ({
          userId: r.userId,
          name: r.user.displayName,
          // Phone numbers are only shown to the owner.
          ...(isOwner ? { phoneNumber: r.user.phoneNumber } : {}),
          role: r.role,
          status: r.status,
        })),
    ],
    invites: invites.map((i) => ({ id: i.id, code: i.code, role: i.role, expiresAt: i.expiresAt })),
  };
}

export async function updateMember(
  organizerId: string,
  eventGroupId: string,
  userId: string,
  input: UpdateMemberInput
) {
  await requireOwner(organizerId, eventGroupId);
  const where = { eventGroupId_userId: { eventGroupId, userId } };
  const member = await prisma.rolePermission.findUnique({ where });
  if (!member) throw new AppError(404, "Member not found");
  const updated = await prisma.rolePermission.update({
    where,
    data: { ...(input.role ? { role: input.role } : {}), ...(input.approve ? { status: "active" } : {}) },
  });
  return { userId, role: updated.role, status: updated.status };
}

/** The owner removes anyone; a member may remove themselves (leave). */
export async function removeMember(organizerId: string, eventGroupId: string, userId: string) {
  if (organizerId !== userId) await requireOwner(organizerId, eventGroupId);
  const result = await prisma.rolePermission.deleteMany({ where: { eventGroupId, userId } });
  if (result.count === 0) throw new AppError(404, "Member not found");
  return { removed: true };
}
