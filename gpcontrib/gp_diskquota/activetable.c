/* -------------------------------------------------------------------------
 *
 * activetable.c
 *
 * This code is responsible for detecting active table for databases
 *
 * Copyright (C) 2013, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		contrib/diskquota/activetable.c
 *
 * -------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/htup_details.h"
#include "catalog/indexing.h"
#include "catalog/pg_class.h"
#include "catalog/pg_type.h"
#include "cdb/cdbbufferedappend.h"
#include "executor/spi.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "storage/shmem.h"
#include "storage/smgr.h"
#include "utils/builtins.h"
#include "utils/fmgroids.h"
#include "cdb/cdbvars.h"
#include "utils/relfilenodemap.h"

#include "activetable.h"
#include "diskquota.h"

HTAB *active_tables_map = NULL;
static BufferedAppendWrite_hook_type prev_BufferedAppendWrite_hook = NULL;
static SmgrStat_hook_type prev_SmgrStat_hook = NULL;
static ScanKeyData relfilenode_skey[2];

static void report_active_table_SmgrStat(SMgrRelation reln);
static void report_active_table_AO(BufferedAppend *bufferedAppend);
HTAB* get_active_tables(void);
void init_active_table_hook(void);
void init_shm_worker_active_tables(void);
void init_lock_active_tables(void);
void init_relfilenode_key(void);

/*
 * Register smgr hook to detect active table.
 */
void
init_active_table_hook(void)
{
	prev_SmgrStat_hook = SmgrStat_hook;
	SmgrStat_hook = report_active_table_SmgrStat;
	prev_BufferedAppendWrite_hook = BufferedAppendWrite_hook;
	BufferedAppendWrite_hook = report_active_table_AO;
}

/*
 * Init active_tables_map shared memory
 */
void
init_shm_worker_active_tables(void)
{
	HASHCTL ctl;
	memset(&ctl, 0, sizeof(ctl));

	ctl.keysize = sizeof(DiskQuotaActiveTableEntry);
	ctl.entrysize = sizeof(DiskQuotaActiveTableEntry);
	ctl.hash = tag_hash;

	active_tables_map = ShmemInitHash ("active_tables",
										diskquota_max_active_tables,
										diskquota_max_active_tables,
										&ctl,
										HASH_ELEM | HASH_FUNCTION);
}

/*
 * Init lock of active table map 
 */
void init_lock_active_tables(void)
{
	bool found = false;
	active_table_shm_lock = ShmemInitStruct("disk_quota_active_table_shm_lock",
											sizeof(disk_quota_shared_state),
											&found);

	if (!found)
	{
		active_table_shm_lock->lock = LWLockAssign();
	}
}

/*
 * Init relfilenode key to index search table oid 
 * given relfilenode and tablespace.
 */
void
init_relfilenode_key(void)
{
	int			i;

	/* build skey */
	MemSet(&relfilenode_skey, 0, sizeof(relfilenode_skey));

	for (i = 0; i < 2; i++)
	{
		fmgr_info_cxt(F_OIDEQ,
					  &relfilenode_skey[i].sk_func,
					  CacheMemoryContext);
		relfilenode_skey[i].sk_strategy = BTEqualStrategyNumber;
		relfilenode_skey[i].sk_subtype = InvalidOid;
		relfilenode_skey[i].sk_collation = InvalidOid;
	}

	relfilenode_skey[0].sk_attno = Anum_pg_class_reltablespace;
	relfilenode_skey[1].sk_attno = Anum_pg_class_relfilenode;
}

/*
 * Get local active table with table oid and table size info.
 * This function first copies active table map from shared memory 
 * to local active table map with refilenode info. Then traverses
 * the local map and find corresponding table oid and table file 
 * size. Finnaly stores them into local active table map and return.
 */
HTAB* get_active_tables()
{
	HASHCTL ctl;
	HTAB *local_active_table_file_map = NULL;
	HTAB *local_active_table_stats_map = NULL;
	HASH_SEQ_STATUS iter;
	DiskQuotaActiveTableFileEntry *active_table_file_entry;
	DiskQuotaActiveTableEntry *active_table_entry;

	Oid relOid;

	memset(&ctl, 0, sizeof(ctl));
	ctl.keysize = sizeof(DiskQuotaActiveTableFileEntry);
	ctl.entrysize = sizeof(DiskQuotaActiveTableFileEntry);
	ctl.hcxt = CurrentMemoryContext;
	ctl.hash = tag_hash;

	local_active_table_file_map = hash_create("local active table map with relfilenode info",
								1024,
								&ctl,
								HASH_ELEM | HASH_CONTEXT | HASH_FUNCTION);

	/* Move active table from shared memory to local active table map */
	LWLockAcquire(active_table_shm_lock->lock, LW_EXCLUSIVE);

	PG_TRY();
	{
		hash_seq_init(&iter, active_tables_map);

		while ((active_table_file_entry = (DiskQuotaActiveTableFileEntry *) hash_seq_search(&iter)) != NULL)
		{
			bool  found;
			DiskQuotaActiveTableFileEntry *entry;

			if (active_table_file_entry->dbid != MyDatabaseId)
			{
				continue;
			}

			/* Add the active table entry into local hash table*/
			entry = hash_search(local_active_table_file_map, active_table_file_entry, HASH_ENTER, &found);
			if (entry)
				*entry = *active_table_file_entry;
			hash_search(active_tables_map, active_table_file_entry, HASH_REMOVE, NULL);
		}
	}
	PG_CATCH();
	{
		/*
		 * when code comes here, it's out of memory.
		 * But, it's better to run continuely.
		 */
		LWLockRelease(active_table_shm_lock->lock);
		PG_RE_THROW();
	}
	PG_END_TRY();
	LWLockRelease(active_table_shm_lock->lock);

	memset(&ctl, 0, sizeof(ctl));
	ctl.keysize = sizeof(Oid);
	ctl.entrysize = sizeof(DiskQuotaActiveTableEntry);
	ctl.hcxt = CurrentMemoryContext;
	ctl.hash = oid_hash;

	local_active_table_stats_map = hash_create("local active table map with relfilenode info",
								1024,
								&ctl,
								HASH_ELEM | HASH_CONTEXT | HASH_FUNCTION);

	/* traverse local active table map and calculate their file size. */
	hash_seq_init(&iter, local_active_table_file_map);
	/* scan whole local map, get the oid of each table and calculate the size of them */
	while ((active_table_file_entry = (DiskQuotaActiveTableFileEntry *) hash_seq_search(&iter)) != NULL)
	{
		bool found;
		
		relOid = RelidByRelfilenode(active_table_file_entry->tablespaceoid, active_table_file_entry->relfilenode);

		active_table_entry = hash_search(local_active_table_stats_map, &relOid, HASH_ENTER, &found);
		if (active_table_entry)
		{
			active_table_entry->tableoid = relOid;
			active_table_entry->tablesize = 0;
		}
	}
	elog(LOG, "active table number is:%ld", hash_get_num_entries(local_active_table_file_map));
	hash_destroy(local_active_table_file_map);
	return local_active_table_stats_map;
}

/*
 * Common function for reporting active tables, used by smgr and ao
 */
 
static void report_active_table_helper(const RelFileNodeBackend *relFileNode)
{
	DiskQuotaActiveTableFileEntry *entry;
	DiskQuotaActiveTableFileEntry item;
	bool found = false;

	MemSet(&item, 0, sizeof(DiskQuotaActiveTableFileEntry));
	item.dbid = relFileNode->node.dbNode;
	item.relfilenode = relFileNode->node.relNode;
	item.tablespaceoid = relFileNode->node.spcNode;

	LWLockAcquire(active_table_shm_lock->lock, LW_EXCLUSIVE);
	entry = hash_search(active_tables_map, &item, HASH_ENTER_NULL, &found);
	if (entry && !found)
		*entry = item;
	LWLockRelease(active_table_shm_lock->lock);

	if (!found && entry == NULL) {
		/* We may miss the file size change of this relation at current refresh interval.*/
		ereport(WARNING, (errmsg("Share memory is not enough for active tables.")));
	}
}
/*
 *  Hook function in smgr to report the active table
 *  information and stroe them in active table shared memory
 *  diskquota worker will consuming these active tables and
 *  recalculate their file size to update diskquota model.
 */
static void
report_active_table_SmgrStat(SMgrRelation reln)
{
	if (prev_SmgrStat_hook)
		(*prev_SmgrStat_hook)(reln);

	report_active_table_helper(&reln->smgr_rnode);
}

/*
 * Hook function in BufferedAppendWrite to report the active table, used by
 * diskquota
 */
static void
report_active_table_AO(BufferedAppend *bufferedAppend)
{
	if (prev_BufferedAppendWrite_hook)
		(*prev_BufferedAppendWrite_hook)(bufferedAppend);
	report_active_table_helper(&bufferedAppend->relFileNode);
}

HTAB*
get_all_tables_size(void)
{
	HTAB *local_table_stats_map = NULL;
	HASHCTL ctl;
	HeapTuple tuple;
	Relation classRel;
	HeapScanDesc relScan;


	memset(&ctl, 0, sizeof(ctl));
	ctl.keysize = sizeof(Oid);
	ctl.entrysize = sizeof(DiskQuotaActiveTableEntry);
	ctl.hcxt = CurrentMemoryContext;
	ctl.hash = oid_hash;

	local_table_stats_map = hash_create("local active table map with relfilenode info",
	                                    1024,
	                                    &ctl,
	                                    HASH_ELEM | HASH_CONTEXT | HASH_FUNCTION);


	classRel = heap_open(RelationRelationId, AccessShareLock);
	relScan = heap_beginscan_catalog(classRel, 0, NULL);


	while ((tuple = heap_getnext(relScan, ForwardScanDirection)) != NULL)
	{
		Oid relOid;
		DiskQuotaActiveTableEntry *entry;

		Form_pg_class classForm = (Form_pg_class) GETSTRUCT(tuple);
		if (classForm->relkind != RELKIND_RELATION &&
		    classForm->relkind != RELKIND_MATVIEW)
			continue;
		relOid = HeapTupleGetOid(tuple);

		/* ignore system table*/
		if (relOid < FirstNormalObjectId)
			continue;

		entry = (DiskQuotaActiveTableEntry *) hash_search(local_table_stats_map, &relOid, HASH_ENTER, NULL);

		entry->tableoid = relOid;
		entry->tablesize = (Size) DatumGetInt64(DirectFunctionCall1(pg_total_relation_size,
		                                                     ObjectIdGetDatum(relOid)));

	}

	heap_endscan(relScan);
	heap_close(classRel, AccessShareLock);

	return local_table_stats_map;
}
