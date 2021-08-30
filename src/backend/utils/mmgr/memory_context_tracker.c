//
// Created by Hao Wu on 8/30/21.
//

#ifndef MEMORY_CONTEXT_TRACKER

#define MEMORY_CONTEXT_INIT(m) do{}while(0)
#define MEMORY_CONTEXT_ALLOC(m, filename, lineno, ptr) do{}while(0)
#define MEMORY_CONTEXT_FREE(m, ptr) do{}while(0)
#define MEMORY_CONTEXT_REALLOC(m, old, new_, filename, lineno) do{}while(0)
#define MEMORY_CONTEXT_RESET(m) do{}while(0)
#define MEMORY_CONTEXT_DELETE(m) do{}while(0)
#define MEMORY_CONTEXT_DUMP(m, file) do{}while(0)

#else

#define MEMORY_CONTEXT_INIT(m) mt_init((struct MemoryTracker*)(m)->mc_tracker)
#define MEMORY_CONTEXT_ALLOC(m, filename, lineno, ptr) \
    mt_alloc((struct MemoryTracker*)(m)->mc_tracker, (filename), (lineno), (ptr))
#define MEMORY_CONTEXT_FREE(m, ptr) mt_free((struct MemoryTracker*)(m)->mc_tracker, ptr)
#define MEMORY_CONTEXT_REALLOC(m, old, new_, filename, lineno) \
    mt_realloc((struct MemoryTracker*)(m->mc_tracker), (filename), (lineno), (old), (new_))
#define MEMORY_CONTEXT_RESET(m) mt_reset((struct MemoryTracker*)(m)->mc_tracker)
#define MEMORY_CONTEXT_DELETE(m) mt_reset((struct MemoryTracker*)(m)->mc_tracker)
#define MEMORY_CONTEXT_DUMP(m, file) mt_dump((struct MemoryTracker*)(m)->mc_tracker)

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

struct TrackerItem {
  // key, filename are literal value
  const char *filename;
  int32_t lineno;
  uint32_t count;

  uint32_t cap;
  intptr_t *ptrs;
};

static void tracker_item_init(struct TrackerItem *p, const char *filename, int lineno)
{
  p->filename = filename;
  p->lineno = lineno;
  p->count = 0;
  p->cap = 0;
  p->ptrs = (void*)0;
}
static void tracker_item_alloc(struct TrackerItem *ti, void *ptr)
{
  if (ti->count == ti->cap) {
    uint32_t new_cap = ti->cap + 8;
    intptr_t *P;
    if (ti->ptrs)
      P = realloc(ti->ptrs, sizeof(*P) * new_cap);
    else
      P = malloc(new_cap * sizeof(*P));
    if (!P)
      abort();
    ti->cap = new_cap;
    ti->ptrs = P;
  }
  assert(ti->count < ti->cap);
  int l = 0, r = ti->count - 1;
  intptr_t key = (intptr_t)ptr;
  while (l <= r) {
    int m = l + (r - l)/2;
    intptr_t rc = ti->ptrs[m] - key;
    if (rc == 0)
      assert(!"pointer has been tracked");
    if (rc < 0) {
      l = m + 1;
    } else {
      r = m - 1;
    }
  }
  if (l < (int)ti->count) {
    size_t n = ti->count - l;
    memmove(&ti->ptrs[l+1], &ti->ptrs[l], sizeof(key) * n);
  }
  ti->ptrs[l] = key;
  ti->count++;
}

// 1: success
// 0: not found
static int tracker_item_try_free(struct TrackerItem *ti, void *ptr)
{
  int l = 0, r = ti->count -1;
  int m;
  intptr_t rc;
  intptr_t key = (intptr_t)ptr;
  while (l <= r) {
    m = l + (r - l)/2;
    rc = ti->ptrs[m] - key;
    if (rc == 0) {
      // found pointer
      if (m + 1 != ti->count) {
        // move pointers
        size_t n = ti->count - m -1;
        memmove(&ti->ptrs[m], &ti->ptrs[m+1], sizeof(key) * n);
      }
      ti->count--;
      return 1;
    }
    if (rc < 0) {
      l = m + 1;
    } else {
      r = m - 1;
    }
  }
  return 0;
}
static void tracker_item_destroy(struct TrackerItem *ti)
{
  if (ti->ptrs)
    free(ti->ptrs);
  ti->ptrs = (void*)0;
  ti->count = ti->cap = 0;
}

struct MemoryTracker {
  struct TrackerItem *items;
  uint32_t cap;
  uint32_t len;
};

static int TrackerItem_cmp(const void *a, const void *b)
{
  const struct TrackerItem *x = (const struct TrackerItem *)a;
  const struct TrackerItem *y = (const struct TrackerItem *)b;
  if (x->lineno != y->lineno)
    return x->lineno - y->lineno;
  return (int)((intptr_t)x->filename - (intptr_t)y->filename);
}
static struct TrackerItem *mt_search_item(const struct MemoryTracker *mt, const char *filename, uint32_t lineno)
{
  struct TrackerItem key = {
          .filename = filename,
          .lineno = lineno,
  };
  if (mt->len == 0)
    return (void*)0;

  return bsearch(&key, mt->items, mt->len, sizeof(key), TrackerItem_cmp);
}
static inline void mt_init(struct MemoryTracker *mt)
{
  mt->items = (void*)0;
  mt->cap = mt->len = 0;
}
static struct TrackerItem *mt_alloc_tracker_item(struct MemoryTracker *mt, const char *filename, int32_t lineno)
{
  struct TrackerItem *p;
  struct TrackerItem key = {
          .filename = filename,
          .lineno = lineno,
  };

  if (mt->len == mt->cap) {
    // grow array
    uint32_t new_cap = mt->cap + 8;

    if (mt->items)
      p = realloc(mt->items, new_cap * sizeof(*p));
    else
      p = malloc(new_cap * sizeof(*p));
    if (!p)
      abort();
    mt->cap = new_cap;
    mt->items = p;
  }
  assert(mt->len < mt->cap);
  int l = 0, r = mt->len-1;

  while (l <= r) {
    int m = l + (r-l)/2;
    p = &mt->items[m];
    int rc = TrackerItem_cmp(p, &key);
    if (rc == 0)
      assert(!"Tracker item already exists");

    if(rc < 0) {
      l = m + 1;
    }else {
      r = m - 1;
    }
  }
  if (l < (int)mt->len) {
    size_t n = mt->len - (uint32_t)l;
    memmove(&mt->items[l+1], &mt->items[l], sizeof(key) * n);
  }
  p = &mt->items[l];
  *p = key;
  mt->len++;
  return p;
}

static inline void mt_alloc(struct MemoryTracker *mt, const char *filename, int32_t lineno, void *ptr)
{
  struct TrackerItem *item;
  item = mt_search_item(mt, filename, lineno);
  if (!item) {
    item = mt_alloc_tracker_item(mt, filename, lineno);
  }
  assert(item);
  tracker_item_alloc(item, ptr);

}
static inline void mt_free(struct MemoryTracker *mt, void *ptr)
{
  for (unsigned i = 0; i < mt->len; i++) {
    struct TrackerItem *p = &mt->items[i];
    if (tracker_item_try_free(p, ptr)) {
      if (p->count == 0) {
        tracker_item_destroy(p);
        if (i + 1 != mt->len) {
          size_t n = mt->len - i - 1;
          memmove(p, p + 1, sizeof(*p) * n);
        }
        mt->len--;
      }
      return;
    }
  }
  assert(!"No tracked item to free");
}
static inline void mt_realloc(struct MemoryTracker *mt, const char *filename, int lineno, void *old, void *_new)
{
  mt_free(mt, old);
  mt_alloc(mt, filename, lineno, _new);
}
static inline void mt_reset(struct MemoryTracker *mt)
{
  unsigned i;
  for (i = 0; i < mt->len; i++) {
    tracker_item_destroy(&mt->items[i]);
  }
  if (mt->items)
    free(mt->items);
  mt->items = (void*)0;
  mt->len = mt->cap = 0;
}
static inline void mt_delete(struct MemoryTracker *mt)
{
  mt_reset(mt);
}

static void mt_dump_count(struct MemoryTracker *mt, FILE *file)
{
  fprintf(file, "objects = %d\n", mt->len);
  for (unsigned i = 0; i < mt->len; i++) {
    struct TrackerItem *ti = &mt->items[i];
    fprintf(file, "%s@%d: %u\n", ti->filename, ti->lineno, ti->count);
  }
}

#endif
