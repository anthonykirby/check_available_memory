Nagios plugin _check_available_memory_
======================================

 - provides a better estimate of "free" memory than standard plugin
 - uses the kernel's "MemAvailable" metric
 - degrades gracefully to less accurate metrics if this isn't present<br>
    (1st choice) MemAvailable<br>
    (2nd choice) MemFree + Buffers + Cached + SReclaimable<br>
    (3rd choice) MemFree + Buffers + Cached

Usage
-----

- standard Nagios parameters are used for _WARNING_/_CRITICAL_ limits, but in this case we expect to be triggering on a low value not a high value, so to warn at 25% use option "-w 25:" (note the trailing colon)
- both verbose "-v" and very verbose "-vv" return more detail
 
- Warn at 25%, critical at 10%<br>
`$ ./check_available_memory.pl -w 25: -c 10:`<br>
`$ ./check_available_memory.pl --warning=25: --critical=10:`

- Online help<br>
`$ ./check_available_memory.pl -h`


Licence
-------

See attached LICENCE.txt

