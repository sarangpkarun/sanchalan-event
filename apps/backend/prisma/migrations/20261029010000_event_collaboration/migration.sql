-- CreateEnum
CREATE TYPE "MemberStatus" AS ENUM ('active', 'pending');

-- AlterTable
ALTER TABLE "role_permissions" ADD COLUMN "status" "MemberStatus" NOT NULL DEFAULT 'active';

-- CreateIndex
CREATE UNIQUE INDEX "role_permissions_event_group_id_user_id_key" ON "role_permissions"("event_group_id", "user_id");

-- CreateTable
CREATE TABLE "event_invites" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "event_group_id" UUID NOT NULL,
    "role" "EventGroupRole" NOT NULL,
    "created_by" UUID NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "revoked_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "event_invites_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "event_invites_code_key" ON "event_invites"("code");

-- CreateIndex
CREATE INDEX "event_invites_event_group_id_idx" ON "event_invites"("event_group_id");

-- AddForeignKey
ALTER TABLE "event_invites" ADD CONSTRAINT "event_invites_event_group_id_fkey" FOREIGN KEY ("event_group_id") REFERENCES "event_groups"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
