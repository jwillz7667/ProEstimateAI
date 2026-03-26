const DEFAULT_PAGE_SIZE = 25;

export interface PaginationParams {
  cursor?: string;
  pageSize?: number;
}

export interface PaginationResult<T> {
  items: T[];
  nextCursor: string | null;
}

export function parsePagination(query: { cursor?: string; page_size?: string }): PaginationParams {
  return {
    cursor: query.cursor || undefined,
    pageSize: query.page_size ? Math.min(parseInt(query.page_size, 10), 100) : DEFAULT_PAGE_SIZE,
  };
}

export function paginateResults<T extends { id: string }>(
  items: T[],
  pageSize: number = DEFAULT_PAGE_SIZE
): PaginationResult<T> {
  if (items.length > pageSize) {
    return {
      items: items.slice(0, pageSize),
      nextCursor: items[pageSize - 1].id,
    };
  }
  return { items, nextCursor: null };
}

export function buildCursorWhere(cursor?: string): {
  cursor?: { id: string };
  skip?: number;
} {
  if (!cursor) return {};
  return { cursor: { id: cursor }, skip: 1 };
}
