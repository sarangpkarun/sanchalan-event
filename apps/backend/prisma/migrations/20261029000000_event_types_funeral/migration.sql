-- Replace the 'religious' event type with 'funeral'. Existing 'religious' rows become 'custom'.
CREATE TYPE "EventType_new" AS ENUM ('wedding', 'birthday', 'corporate', 'funeral', 'engagement_only', 'custom');

ALTER TABLE "vendor_categories" ALTER COLUMN "applicable_event_types" TYPE TEXT[] USING "applicable_event_types"::TEXT[];
ALTER TABLE "task_categories" ALTER COLUMN "applicable_event_types" TYPE TEXT[] USING "applicable_event_types"::TEXT[];
ALTER TABLE "event_groups" ALTER COLUMN "event_type" TYPE TEXT USING "event_type"::TEXT;
ALTER TABLE "task_templates" ALTER COLUMN "event_type" TYPE TEXT USING "event_type"::TEXT;

UPDATE "event_groups" SET "event_type" = 'custom' WHERE "event_type" = 'religious';
UPDATE "task_templates" SET "event_type" = 'custom' WHERE "event_type" = 'religious';
UPDATE "vendor_categories" SET "applicable_event_types" = array_remove("applicable_event_types", 'religious');
UPDATE "task_categories" SET "applicable_event_types" = array_remove("applicable_event_types", 'religious');

ALTER TABLE "vendor_categories" ALTER COLUMN "applicable_event_types" TYPE "EventType_new"[] USING "applicable_event_types"::"EventType_new"[];
ALTER TABLE "task_categories" ALTER COLUMN "applicable_event_types" TYPE "EventType_new"[] USING "applicable_event_types"::"EventType_new"[];
ALTER TABLE "event_groups" ALTER COLUMN "event_type" TYPE "EventType_new" USING "event_type"::"EventType_new";
ALTER TABLE "task_templates" ALTER COLUMN "event_type" TYPE "EventType_new" USING "event_type"::"EventType_new";

DROP TYPE "EventType";
ALTER TYPE "EventType_new" RENAME TO "EventType";
