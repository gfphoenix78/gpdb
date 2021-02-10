-- make sure the status of the coordinator and standby
-- are in good status
select dbid,content,role,preferred_role,status
  from gp_segment_configuration
  where content=-1
  order by dbid;

-- start_ignore
!\retcode gpconfig -c synchronous_standby_names -v '*' --masteronly;
!\retcode gpstop -u;
-- end_ignore
show synchronous_standby_names;

-- case 1: bring up the standby should make the session 1 continue to run
1: select pg_ctl(datadir, 'stop') from gp_segment_configuration where content=-1 and role='m';
1>: create table t_block_coordinator(i int);
2: select pg_sleep(1);
2: select oid,relname from pg_class where relname = 't_block_coordinator';

2: select pg_ctl_start(datadir, port, 'dispatch') from gp_segment_configuration where content=-1 and role='m';
1<:
2: select relname from pg_class where relname = 't_block_coordinator';
2: drop table t_block_coordinator;

-- case 2: set synchronous_standby_names to an empty string
1: select pg_ctl(datadir, 'stop') from gp_segment_configuration where content=-1 and role='m';
1>: create table t_block_coordinator2(i int);
2: select pg_sleep(1);
2: select oid,relname from pg_class where relname = 't_block_coordinator2';

-- start_ignore
!\retcode gpconfig -c synchronous_standby_names -v '' --masteronly;
!\retcode gpstop -u;
-- end_ignore
show synchronous_standby_names;

1<:
2: select relname from pg_class where relname = 't_block_coordinator2';
2: drop table t_block_coordinator2;

-- restore the test environment
2: select pg_ctl_start(datadir, port, 'dispatch') from gp_segment_configuration where content=-1 and role='m';

-- start_ignore
!\retcode gpconfig -c synchronous_standby_names -v '*' --masteronly;
!\retcode gpstop -u;
-- end_ignore
show synchronous_standby_names;

select content,role,preferred_role,status
  from gp_segment_configuration
  where content=-1
  order by role;

