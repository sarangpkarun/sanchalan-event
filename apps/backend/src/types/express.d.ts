import type { AdminRole, AuthRole } from "@setzo/shared-types";

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string; role: AuthRole; adminRole?: AdminRole };
    }
  }
}

export {};
