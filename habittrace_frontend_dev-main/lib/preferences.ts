export interface Preferences {
  defaultDuration: number;
  workStart: string;
  workEnd: string;
}

export function readPreferences(
  metadata: Record<string, unknown> = {},
): Preferences {
  const raw = (metadata.planning_preferences ?? {}) as Partial<Preferences>;
  const validTime = (v: unknown): v is string =>
    typeof v === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(v);
  return {
    defaultDuration:
      typeof raw.defaultDuration === "number" &&
      raw.defaultDuration >= 5 &&
      raw.defaultDuration <= 480
        ? raw.defaultDuration
        : 30,
    workStart: validTime(raw.workStart) ? raw.workStart : "09:00",
    workEnd: validTime(raw.workEnd) ? raw.workEnd : "22:00",
  };
}
