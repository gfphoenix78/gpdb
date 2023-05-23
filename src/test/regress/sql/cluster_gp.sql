-- Test CLUSTER with append optimized storage
CREATE TABLE cluster_ao_table(
	id int,
	fname text,
	lname text,
	address1 text,
	address2 text,
	city text,
	state text,
	zip text)
WITH (appendonly=true)
DISTRIBUTED BY (id);

INSERT INTO cluster_ao_table (id, fname, lname, address1, address2, city, state, zip)
SELECT i, 'Jon_' || i, 'Roberts_' || i, i || ' Main Street', 'Apartment ' || i, 'New York', 'NY', i::text
FROM generate_series(1, 10000) AS i;

CREATE INDEX ON cluster_ao_table (id);

BEGIN;
CLUSTER cluster_ao_table USING cluster_ao_table_id_idx;
ABORT;
CLUSTER cluster_ao_table USING cluster_ao_table_id_idx;

SELECT * FROM cluster_ao_table WHERE id = 10;

DROP TABLE cluster_ao_table;

-- Test CLUSTER with append optimized columnar storage
CREATE TABLE cluster_ao_table(
	id int,
	fname text,
	lname text,
	address1 text,
	address2 text,
	city text,
	state text,
	zip text)
WITH (appendonly=true, orientation=column)
DISTRIBUTED BY (id);

INSERT INTO cluster_ao_table (id, fname, lname, address1, address2, city, state, zip)
SELECT i, 'Jon_' || i, 'Roberts_' || i, i || ' Main Street', 'Apartment ' || i, 'New York', 'NY', i::text
FROM generate_series(1, 10000) AS i;

CREATE INDEX ON cluster_ao_table (id);

BEGIN;
CLUSTER cluster_ao_table USING cluster_ao_table_id_idx;
ABORT;
CLUSTER cluster_ao_table USING cluster_ao_table_id_idx;

SELECT * FROM cluster_ao_table WHERE id = 10;

DROP TABLE cluster_ao_table;

-- Test transactional safety of CLUSTER against heap
CREATE TABLE cluster_foo (a int, b varchar, c int) DISTRIBUTED BY (a);
INSERT INTO cluster_foo SELECT i, 'initial insert' || i, i FROM generate_series(1,10000)i;
CREATE index cluster_ifoo on cluster_foo using btree (b);
-- execute cluster in a transaction but don't commit the transaction
BEGIN;
CLUSTER cluster_foo USING cluster_ifoo;
ABORT;
-- try cluster again
CLUSTER cluster_foo USING cluster_ifoo;
DROP TABLE cluster_foo;

-- Test that reltuples and relpages are populated on both QE and QD post-CLUSTER.
CREATE TABLE cluster_stats(a int, b int);
CREATE INDEX ON cluster_stats(a);
INSERT INTO cluster_stats SELECT a, a FROM generate_series(1, 100)a;
ANALYZE cluster_stats;

SELECT gp_segment_id, relpages, reltuples FROM gp_dist_random('pg_class')
WHERE relname='cluster_stats'
UNION
SELECT -1, relpages, reltuples FROM pg_class
WHERE relname='cluster_stats';

DELETE FROM cluster_stats where a % 3 = 1;
CLUSTER cluster_stats USING cluster_stats_a_idx;

SELECT gp_segment_id, relpages, reltuples FROM gp_dist_random('pg_class')
WHERE relname='cluster_stats'
UNION
SELECT -1, relpages, reltuples FROM pg_class
WHERE relname='cluster_stats';
