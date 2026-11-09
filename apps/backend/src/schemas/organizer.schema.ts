import { z } from "zod";

export const updateProfileSchema = z.object({
  displayName: z.string().min(1),
  // Only a default suggestion now: each event picks its own organizer type.
  organizerType: z.enum(["individual", "family", "company", "committee"]).optional(),
});
export type UpdateProfileInput = z.infer<typeof updateProfileSchema>;
