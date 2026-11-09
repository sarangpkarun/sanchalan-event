-- AlterTable: the organizer type moves from the account to the event.
ALTER TABLE "event_groups" ADD COLUMN "organizer_type" "OrganizerType" NOT NULL DEFAULT 'individual';

-- Existing events keep the type their owner had chosen on the profile.
UPDATE "event_groups" eg
SET "organizer_type" = o."organizer_type"
FROM "organizers" o
WHERE eg."organizer_id" = o."id" AND o."organizer_type" IS NOT NULL;
