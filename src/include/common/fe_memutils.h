/*
 *	fe_memutils.h
 *		memory management support for frontend code
 *
 *	Copyright (c) 2003-2014, PostgreSQL Global Development Group
 *
 *	src/include/common/fe_memutils.h
 */
#ifndef FE_MEMUTILS_H
#define FE_MEMUTILS_H

/* "Safe" memory allocation functions --- these exit(1) on failure */
extern char *pg_strdup(const char *in);
extern void *pg_malloc(size_t size);
extern void *pg_malloc0(size_t size);
extern void *pg_realloc(void *pointer, size_t size);
extern void pg_free(void *pointer);


#define palloc(size) pallocImpl((size), __FILE__, __LINE__)
#define palloc0(size) palloc0Impl((size), __FILE__, __LINE__)
#define repalloc(pointer, size) repallocImpl((pointer), (size), __FILE__, __LINE__)
/* Equivalent functions, deliberately named the same as backend functions */
extern char *pstrdup(const char *in);
extern void *pallocImpl(Size size, const char *filename, int lineno);
extern void *palloc0Impl(Size size, const char *filename, int lineno);
extern void *repallocImpl(void *pointer, Size size, const char *filename, int lineno);
extern void pfree(void *pointer);

/* sprintf into a palloc'd buffer --- these are in psprintf.c */
extern char *
psprintf(const char *fmt,...)
__attribute__((format(PG_PRINTF_ATTRIBUTE, 1, 2)));
extern size_t
pvsnprintf(char *buf, size_t len, const char *fmt, va_list args)
__attribute__((format(PG_PRINTF_ATTRIBUTE, 3, 0)));

#endif   /* FE_MEMUTILS_H */
