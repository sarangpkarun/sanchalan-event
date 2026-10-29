import type { NextFunction, Request, Response } from "express";
import { idParamSchema } from "../schemas/event-group.schema.js";
import {
  createInviteSchema,
  inviteParamSchema,
  joinSchema,
  memberParamSchema,
  updateMemberSchema,
} from "../schemas/event-member.schema.js";
import * as members from "../services/event-member.service.js";

type Handler = (req: Request, res: Response) => Promise<void>;
const wrap = (fn: Handler) => (req: Request, res: Response, next: NextFunction) => {
  fn(req, res).catch(next);
};

export const joinHandler = wrap(async (req, res) => {
  const { code } = joinSchema.parse(req.body);
  res.status(200).json(await members.joinByCode(req.auth!.userId, code));
});

export const listMembersHandler = wrap(async (req, res) => {
  const { id } = idParamSchema.parse(req.params);
  res.status(200).json(await members.listMembers(req.auth!.userId, id));
});

export const createInviteHandler = wrap(async (req, res) => {
  const { id } = idParamSchema.parse(req.params);
  const input = createInviteSchema.parse(req.body ?? {});
  res.status(201).json(await members.createInvite(req.auth!.userId, id, input));
});

export const revokeInviteHandler = wrap(async (req, res) => {
  const { id, inviteId } = inviteParamSchema.parse(req.params);
  res.status(200).json(await members.revokeInvite(req.auth!.userId, id, inviteId));
});

export const updateMemberHandler = wrap(async (req, res) => {
  const { id, userId } = memberParamSchema.parse(req.params);
  res.status(200).json(await members.updateMember(req.auth!.userId, id, userId, updateMemberSchema.parse(req.body)));
});

export const removeMemberHandler = wrap(async (req, res) => {
  const { id, userId } = memberParamSchema.parse(req.params);
  res.status(200).json(await members.removeMember(req.auth!.userId, id, userId));
});
