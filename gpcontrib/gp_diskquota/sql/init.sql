\! gpconfig -c shared_preload_libraries -v diskquota > /dev/null
-- end_ignore

\! echo $?

\! gpconfig -c diskquota.monitor_databases -v contrib_regression > /dev/null
-- end_ignore

\! echo $?

-- start_ignore
\! gpstop -rai > /dev/null
-- end_ignore

\! echo $?

\! sleep 10
