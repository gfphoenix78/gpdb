select count(1) from gp_segment_configuration;
select dbid, content, role
  from gp_segment_configuration
  where status='d'
  order by dbid;
