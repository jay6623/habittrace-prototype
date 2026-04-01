export function Button({ children }: { children: React.ReactNode }) {
  return (
    <button className="px-4 py-2 bg-accent-emerald text-white rounded-2xl hover:opacity-90">
      {children}
    </button>
  );
}