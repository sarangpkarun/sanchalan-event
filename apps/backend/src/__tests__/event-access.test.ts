import { beforeEach, describe, expect, it, vi } from "vitest";

const prismaMock = vi.hoisted(() => ({
  eventGroup: { findUnique: vi.fn() },
  rolePermission: { findUnique: vi.fn() },
}));
vi.mock("../lib/prisma.js", () => ({ prisma: prismaMock }));

import {
  getEventAccess,
  requireBudgetEdit,
  requireEdit,
  requireOwner,
  requireRead,
} from "../services/event-access.service.js";

const event = (ownerType: string) => ({
  id: "e1",
  organizerId: "owner",
  name: "Wedding",
  organizer: { organizerType: ownerType },
});
const member = (role: string, status = "active") => ({ role, status });

async function status(p: Promise<unknown>): Promise<number> {
  try {
    await p;
    return 200;
  } catch (e) {
    return (e as { status: number }).status;
  }
}

describe("event access", () => {
  beforeEach(() => vi.resetAllMocks());

  it("the creator is owner without a membership row", async () => {
    prismaMock.eventGroup.findUnique.mockResolvedValue(event("family"));
    expect((await getEventAccess("owner", "e1")).role).toBe("owner");
    expect(prismaMock.rolePermission.findUnique).not.toHaveBeenCalled();
  });

  it("an unknown event is 404, a stranger is 403", async () => {
    prismaMock.eventGroup.findUnique.mockResolvedValue(null);
    expect(await status(requireRead("x", "e1"))).toBe(404);
    prismaMock.eventGroup.findUnique.mockResolvedValue(event("family"));
    prismaMock.rolePermission.findUnique.mockResolvedValue(null);
    expect(await status(requireRead("x", "e1"))).toBe(403);
  });

  it("a pending member has no access", async () => {
    prismaMock.eventGroup.findUnique.mockResolvedValue(event("company"));
    prismaMock.rolePermission.findUnique.mockResolvedValue(member("editor", "pending"));
    expect(await status(requireRead("m", "e1"))).toBe(403);
  });

  it("a viewer can read but not edit", async () => {
    prismaMock.eventGroup.findUnique.mockResolvedValue(event("family"));
    prismaMock.rolePermission.findUnique.mockResolvedValue(member("viewer"));
    expect(await status(requireRead("m", "e1"))).toBe(200);
    expect(await status(requireEdit("m", "e1"))).toBe(403);
  });

  it("family editors can change the budget; company editors cannot, approvers can", async () => {
    prismaMock.eventGroup.findUnique.mockResolvedValue(event("family"));
    prismaMock.rolePermission.findUnique.mockResolvedValue(member("editor"));
    expect(await status(requireBudgetEdit("m", "e1"))).toBe(200);

    prismaMock.eventGroup.findUnique.mockResolvedValue(event("company"));
    expect(await status(requireBudgetEdit("m", "e1"))).toBe(403);
    expect(await status(requireEdit("m", "e1"))).toBe(200);

    prismaMock.rolePermission.findUnique.mockResolvedValue(member("approver"));
    expect(await status(requireBudgetEdit("m", "e1"))).toBe(200);
  });

  it("only the creator passes requireOwner", async () => {
    prismaMock.eventGroup.findUnique.mockResolvedValue(event("committee"));
    prismaMock.rolePermission.findUnique.mockResolvedValue(member("approver"));
    expect(await status(requireOwner("m", "e1"))).toBe(403);
    expect(await status(requireOwner("owner", "e1"))).toBe(200);
  });
});
