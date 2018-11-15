/* -------------------------------------------------------------------------
 *
 * enforcment.c
 *
 * This code registers enforcement hooks to cancle the query which exceeds 
 * the quota limit.
 *
 * Copyright (C) 2013, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		contrib/diskquota/enforcement.c
 *
 * -------------------------------------------------------------------------
 */
#include "postgres.h"

#include "cdb/cdbdisp.h"
#include "cdb/cdbdisp_async.h"
#include "executor/executor.h"
#include "storage/bufmgr.h"
#include "utils/resowner.h"
#include "diskquota.h"

static bool quota_check_ExecCheckRTPerms(List *rangeTable, bool ereport_on_violation);
static bool quota_check_DispatcherCheckPerms(void);

static ExecutorCheckPerms_hook_type prev_ExecutorCheckPerms_hook;
static DispatcherCheckPerms_hook_type prev_DispatcherCheckPerms_hook;
static void diskquota_free_callback(ResourceReleasePhase phase, bool isCommit, bool isTopLevel, void *arg);

static List *checked_reloid_list = NIL;

/*
 * Initialize enforcement hooks.
 */
void
init_disk_quota_enforcement(void)
{
	/* enforcement hook before query is loading data */
	prev_ExecutorCheckPerms_hook = ExecutorCheckPerms_hook;
	ExecutorCheckPerms_hook = quota_check_ExecCheckRTPerms;

	/* enforcement hook during query is loading data */
	prev_DispatcherCheckPerms_hook =DispatcherCheckPerms_hook;
	DispatcherCheckPerms_hook = quota_check_DispatcherCheckPerms;
	
	RegisterResourceReleaseCallback(diskquota_free_callback, NULL);
}

/*
 * Reset checked reloid list
 * This maybe called multiple times at different resource relase
 * phase, but it's safe to reset the checked_reloid_list.
 */
static void
diskquota_free_callback(ResourceReleasePhase phase,
					 bool isCommit,
					 bool isTopLevel,
					 void *arg)
{
	if (checked_reloid_list != NIL)
	{
		list_free(checked_reloid_list);
		checked_reloid_list = NIL;
	}
	return;
}
/*
 * Enformcent hook function before query is loading data. Throws an error if 
 * you try to INSERT, UPDATE or COPY into a table, and the quota has been exceeded.
 */
static bool
quota_check_ExecCheckRTPerms(List *rangeTable, bool ereport_on_violation)
{
	ListCell   *l;

	if (checked_reloid_list != NIL)
	{
		list_free(checked_reloid_list);
		checked_reloid_list = NIL;
	}

	foreach(l, rangeTable)
	{
		RangeTblEntry *rte = (RangeTblEntry *) lfirst(l);

		/* see ExecCheckRTEPerms() */
		if (rte->rtekind != RTE_RELATION)
			continue;

		/*
		 * Only check quota on inserts. UPDATEs may well increase
		 * space usage too, but we ignore that for now.
		 */
		if ((rte->requiredPerms & ACL_INSERT) == 0 && (rte->requiredPerms & ACL_UPDATE) == 0)
			continue;

		/* Perform the check as the relation's owner and namespace */
		quota_check_common(rte->relid);
		checked_reloid_list = lappend_oid(checked_reloid_list, rte->relid);
	}
	return true;
}

/*
 * Enformcent hook function when query is loading data. Throws an error if
 * the quota has been exceeded.
 */
static bool
quota_check_DispatcherCheckPerms(void)
{
	ListCell   *lc;
	if(checked_reloid_list == NIL)
		return true;
	/* Perform the check as the relation's owner and namespace */
	foreach(lc, checked_reloid_list)
	{
		Oid relid = (Oid)lfirst_oid(lc);
		quota_check_common(relid);
	}
	return true;
}
