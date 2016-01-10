--
-- eventsname.sql
--
-- This sqlplus script generates a sed script file to be used to replace oracle wait event numbers with event names
-- 
-- L.C. Aug 2014
--
-- Borrowed by Frits Hoogland for stapflames (jan 10, 2016)

set echo off pages 0 lines 200 feed off head off sqlblanklines off trimspool on trimout on

spool eventsname.sed

select 's/\<event#='||to_char(event#)||'\>/'||'event='||replace(name,'/','\/')||'/g' SED from v$event_name order by event# desc;

spool off
exit
