"use client";

import { useEffect, useState } from "react";
import { useAuth } from "@/app/providers";
import { avatarInitials, readAvatarUrl } from "@/lib/avatar";

/** Read-only avatar for places like Insights (no menu). */
export default function ProfileAvatar({
  size = "md",
  className = "",
}: {
  size?: "sm" | "md" | "lg";
  className?: string;
}) {
  const { user, displayName } = useAuth();
  const avatarUrl = readAvatarUrl(user);
  const initials = avatarInitials(displayName, user?.email);
  const [imageBroken, setImageBroken] = useState(false);

  useEffect(() => {
    setImageBroken(false);
  }, [avatarUrl]);

  const dimension =
    size === "lg"
      ? "h-14 w-14 text-base"
      : size === "sm"
        ? "h-9 w-9 text-xs"
        : "h-11 w-11 text-sm";

  return (
    <span
      aria-hidden="true"
      className={`grid shrink-0 place-items-center overflow-hidden rounded-full bg-slate-950 font-bold text-white ring-2 ring-slate-200 ${dimension} ${className}`}
    >
      {avatarUrl && !imageBroken ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          alt=""
          className="h-full w-full object-cover"
          onError={() => setImageBroken(true)}
          src={avatarUrl}
        />
      ) : (
        initials
      )}
    </span>
  );
}
