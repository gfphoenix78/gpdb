-- Test delete disk quota
create schema deleteschema;
select diskquota.set_schema_quota('deleteschema', '1 MB');
set search_path to deleteschema;

create table c (i int);
-- expect failed 
insert into c select generate_series(1,100000000);
select pg_sleep(5);
-- expect fail
insert into c select generate_series(1,100);
select diskquota.set_schema_quota('deleteschema', '-1 MB');
select pg_sleep(5);

insert into c select generate_series(1,100);

drop table c;
reset search_path;
drop schema deleteschema;
