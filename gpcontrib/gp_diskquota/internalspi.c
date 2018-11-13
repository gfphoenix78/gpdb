/* -------------------------------------------------------------------------
 *
 * quotamodel.c
 *
 * This code is responsible for init disk quota model and refresh disk quota
 * model.
 *
 * Copyright (C) 2013, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		contrib/diskquota/quotamodel.c
 *
 * -------------------------------------------------------------------------
 */

#include "postgres.h"

#include <utils/fmgroids.h>
#include <cdb/cdbvars.h>
#include <utils/array.h>
#include "funcapi.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "utils/builtins.h"

#include "diskquota.h"
#include "activetable.h"

/* The results set cache for SRF call*/
typedef struct DiskQuotaSetOFCache
{
	HTAB                *result;
	HASH_SEQ_STATUS     pos;
} DiskQuotaSetOFCache;


static HTAB* get_active_tables_stats(ArrayType *array);

PG_FUNCTION_INFO_V1(diskquota_fetch_table_stat);
Datum
diskquota_fetch_table_stat(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;
	int16 model = PG_GETARG_INT16(0);
	AttInMetadata *attinmeta;
	bool isFirstCall = true;

	HTAB *localCacheTable = NULL;
	DiskQuotaSetOFCache *cache = NULL;
	DiskQuotaActiveTableEntry *results_entry = NULL;

	/* Init the container list in the first call and get the results back */
	if (SRF_IS_FIRSTCALL()) {
		MemoryContext oldcontext;
		TupleDesc tupdesc;

		/* create a function context for cross-call persistence */
		funcctx = SRF_FIRSTCALL_INIT();

		/* switch to memory context appropriate for multiple function calls */
		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		if (Gp_role == GP_ROLE_DISPATCH || Gp_role == GP_ROLE_UTILITY)
		{
			ereport(ERROR, (errmsg("This function must not be called on master or by user")));
		}

		switch (model)
		{
			case 0 :
				localCacheTable = get_all_tables_size();
				break;
			case 1 :
				localCacheTable = get_active_tables();
				break;
			case 2 :
				localCacheTable = get_active_tables_stats(PG_GETARG_ARRAYTYPE_P(1));
				break;
			default:
				ereport(ERROR, (errmsg("Unused model number, transaction will be aborted")));
				break;

		}

		/* total number of active tables to be returned, each tuple contains one active table stat */
		funcctx->max_calls = (uint32) hash_get_num_entries(localCacheTable);

		/*
		 * prepare attribute metadata for next calls that generate the tuple
		 */

		tupdesc = CreateTemplateTupleDesc(3, false);
		TupleDescInitEntry(tupdesc, (AttrNumber) 1, "TABLE_OID",
		                   OIDOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 2, "TABLE_SIZE",
		                   INT8OID, -1, 0);

		attinmeta = TupleDescGetAttInMetadata(tupdesc);
		funcctx->attinmeta = attinmeta;

		/* Prepare SetOf results HATB */
		cache = (DiskQuotaSetOFCache *) palloc(sizeof(DiskQuotaSetOFCache));
		cache->result = localCacheTable;
		hash_seq_init(&(cache->pos), localCacheTable);

		MemoryContextSwitchTo(oldcontext);
	} else {
		isFirstCall = false;
	}

	funcctx = SRF_PERCALL_SETUP();

	if (isFirstCall) {
		funcctx->user_fctx = (void *) cache;
	} else {
		cache = (DiskQuotaSetOFCache *) funcctx->user_fctx;
	}

	/* return the results back to SPI caller */
	while ((results_entry = (DiskQuotaActiveTableEntry *) hash_seq_search(&(cache->pos))) != NULL)
	{
		Datum result;
		Datum values[2];
		bool nulls[2];
		HeapTuple	tuple;

		memset(values, 0, sizeof(values));
		memset(nulls, false, sizeof(nulls));

		values[0] = ObjectIdGetDatum(results_entry->tableoid);
		values[1] = Int64GetDatum(results_entry->tablesize);

		tuple = heap_form_tuple(funcctx->attinmeta->tupdesc, values, nulls);

		result = HeapTupleGetDatum(tuple);

		SRF_RETURN_NEXT(funcctx, result);
	}

	/* finished, do the clear staff */
	hash_destroy(cache->result);
	pfree(cache);
	SRF_RETURN_DONE(funcctx);
}
