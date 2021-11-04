@hostname_address
Feature: hostname_address tests

    Scenario: incremental recovery works with tablespaces
        Given the database is running
          And check if the addresses of wal replication are correct for all pairs
          And a tablespace is created with data
          And user stops all primary processes
          And user can start transactions
         When the user runs "gprecoverseg -a"
         Then gprecoverseg should return a return code of 0
          And the segments are synchronized
          And check if the addresses of wal replication are correct for all pairs
          And the tablespace is valid

        Given another tablespace is created with data
         When the user runs "gprecoverseg -ra"
         Then gprecoverseg should return a return code of 0
          And the segments are synchronized
          And check if the addresses of wal replication are correct for all pairs
          And the tablespace is valid
          And the other tablespace is valid

    Scenario: full recovery works with tablespaces
        Given the database is running
          And check if the addresses of wal replication are correct for all pairs
          And a tablespace is created with data
          And user stops all primary processes
          And user can start transactions
         When the user runs "gprecoverseg -a -F"
         Then gprecoverseg should return a return code of 0
          And the segments are synchronized
          And check if the addresses of wal replication are correct for all pairs
          And the tablespace is valid

        Given another tablespace is created with data
         When the user runs "gprecoverseg -ra"
         Then gprecoverseg should return a return code of 0
          And the segments are synchronized
          And the tablespace is valid
          And the other tablespace is valid
          And the segments are synchronized
          And check if the addresses of wal replication are correct for all pairs

    Scenario: gprecoverseg full recovery displays pg_basebackup progress to the user
        Given the database is running
        And all the segments are running
        And the segments are synchronized
        And check if the addresses of wal replication are correct for all pairs
        And user stops all mirror processes
        When user can start transactions
        And the user runs "gprecoverseg -F -a -s"
        Then gprecoverseg should return a return code of 0
        And gprecoverseg should print "pg_basebackup: base backup completed" to stdout for each mirror
        And gpAdminLogs directory has no "pg_basebackup*" files
        And all the segments are running
        And the segments are synchronized
        And check if the addresses of wal replication are correct for all pairs

    Scenario: gprecoverseg incremental recovery displays pg_rewind progress to the user
        Given the database is running
        And all the segments are running
        And the segments are synchronized
        And check if the addresses of wal replication are correct for all pairs
        And user stops all primary processes
        And user can start transactions
        When the user runs "gprecoverseg -a -s"
        Then gprecoverseg should return a return code of 0
        And gprecoverseg should print "pg_rewind: no rewind required" to stdout for each primary
        And gpAdminLogs directory has no "pg_rewind*" files
        And all the segments are running
        And the segments are synchronized
        And the cluster is rebalanced
        And check if the addresses of wal replication are correct for all pairs

    Scenario: When gprecoverseg incremental recovery uses pg_rewind to recover and an existing postmaster.pid on the killed primary segment corresponds to a non postgres process
        Given the database is running
        And all the segments are running
        And the segments are synchronized
        And check if the addresses of wal replication are correct for all pairs
        And the "primary" segment information is saved
        When the postmaster.pid file on "primary" segment is saved
        And user stops all primary processes
        When user can start transactions
        And we run a sample background script to generate a pid on "primary" segment
        And we generate the postmaster.pid file with the background pid on "primary" segment
        And the user runs "gprecoverseg -a"
        Then gprecoverseg should return a return code of 0
        And gprecoverseg should print "Running pg_rewind on failed segments" to stdout
        And gprecoverseg should not print "Unhandled exception in thread started by <bound method Worker.__bootstrap" to stdout
        And all the segments are running
        And the segments are synchronized
        And check if the addresses of wal replication are correct for all pairs
        When the user runs "gprecoverseg -ra"
        Then gprecoverseg should return a return code of 0
        And gprecoverseg should not print "Unhandled exception in thread started by <bound method Worker.__bootstrap" to stdout
        And the segments are synchronized
        And check if the addresses of wal replication are correct for all pairs
        And the backup pid file is deleted on "primary" segment
        And the background pid is killed on "primary" segment

    Scenario: Pid does not correspond to any running process
        Given the database is running
        And all the segments are running
        And the segments are synchronized
        And check if the addresses of wal replication are correct for all pairs
        And the "primary" segment information is saved
        When the postmaster.pid file on "primary" segment is saved
        And user stops all primary processes
        When user can start transactions
        And we generate the postmaster.pid file with a non running pid on the same "primary" segment
        And the user runs "gprecoverseg -a"
        And gprecoverseg should print "Running pg_rewind on failed segments" to stdout
        Then gprecoverseg should return a return code of 0
        And gprecoverseg should not print "Unhandled exception in thread started by <bound method Worker.__bootstrap" to stdout
        And all the segments are running
        And the segments are synchronized
        And check if the addresses of wal replication are correct for all pairs
        When the user runs "gprecoverseg -ra"
        Then gprecoverseg should return a return code of 0
        And gprecoverseg should not print "Unhandled exception in thread started by <bound method Worker.__bootstrap" to stdout
        And the segments are synchronized
        And check if the addresses of wal replication are correct for all pairs
        And the backup pid file is deleted on "primary" segment
