import { z } from "zod";

const memberRole = z.enum(["editor", "viewer", "approver"]);

export const createInviteSchema = z.object({ role: memberRole.default("editor") });
export type CreateInviteInput = z.infer<typeof createInviteSchema>;

export const joinSchema = z.object({
  code: z
    .string()
    .trim()
    .min(4)
    .max(32)
    .transform((c) => c.toUpperCase().replace(/[\s-]/g, "")),
});
export type JoinInput = z.infer<typeof joinSchema>;

export const updateMemberSchema = z
  .object({ role: memberRole.optional(), approve: z.literal(true).optional() })
  .refine((b) => b.role !== undefined || b.approve, { message: "Nothing to change" });
export type UpdateMemberInput = z.infer<typeof updateMemberSchema>;

export const memberParamSchema = z.object({ id: z.string().uuid(), userId: z.string().uuid() });
export const inviteParamSchema = z.object({ id: z.string().uuid(), inviteId: z.string().uuid() });
