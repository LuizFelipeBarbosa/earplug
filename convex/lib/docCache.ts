import { Doc, Id, TableNames } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";

/** Per-invocation memo over `ctx.db.get` and `ctx.storage.getUrl`, for
 * hydration loops that revisit the same venues, bands or flyers row after row.
 * The memo never observes writes, so in a mutation take it for a read phase
 * that finishes before the first patch. */
export type DocCache = ReturnType<typeof docCache>;

export function docCache(ctx: QueryCtx | MutationCtx) {
  const docs = new Map<string, Promise<unknown>>();
  const urls = new Map<string, Promise<string | null>>();
  return {
    get<T extends TableNames>(id: Id<T>): Promise<Doc<T> | null> {
      let pending = docs.get(id);
      if (pending === undefined) {
        pending = ctx.db.get(id);
        docs.set(id, pending);
      }
      return pending as Promise<Doc<T> | null>;
    },
    getUrl(storageId: Id<"_storage">): Promise<string | null> {
      let pending = urls.get(storageId);
      if (pending === undefined) {
        pending = ctx.storage.getUrl(storageId);
        urls.set(storageId, pending);
      }
      return pending;
    },
  };
}
