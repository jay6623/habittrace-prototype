"use client";

import { useState } from "react";
import { memberInitial } from "@/lib/group";

export default function MemberAvatar({
  name,
  avatarUrl,
  className = "h-11 w-11 text-sm",
}: {
  name: string;
  avatarUrl?: string | null;
  className?: string;
}) {
  const [brokenUrl, setBrokenUrl] = useState<string | null>(null);
  const showImage = Boolean(avatarUrl?.trim()) && avatarUrl !== brokenUrl;

  return (
    <div
      aria-hidden="true"
      className={`grid shrink-0 place-items-center overflow-hidden rounded-full bg-slate-900 font-bold text-white ${className}`}
    >
      {showImage ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          alt=""
          className="h-full w-full object-cover"
          onError={() => setBrokenUrl(avatarUrl ?? null)}
          src={avatarUrl!}
        />
      ) : (
        memberInitial(name)
      )}
    </div>
  );
}
