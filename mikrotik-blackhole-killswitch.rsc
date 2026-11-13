:local blackholeDistance 10;
:local excludeTables {"main"};
:local prefixFilter "";
:local tag "killswitch";

:foreach tId in=[/routing table find where !dynamic] do={
    :local tName [/routing table get $tId name];
    :local skip false;
    :foreach ex in=$excludeTables do={
        :if ($tName = $ex) do={ :set skip true; };
    };
    :if ($prefixFilter != "" && [:find $tName $prefixFilter] != 0) do={ :set skip true; };
    :if ($skip = false) do={
        :if ([:len [/ip route find where routing-table=$tName blackhole=yes dst-address="0.0.0.0/0"]] = 0) do={
            /ip route add dst-address="0.0.0.0/0" blackhole distance=$blackholeDistance routing-table=$tName comment=$tag;
        };
        :if ([:len [/ipv6 route find where routing-table=$tName blackhole=yes dst-address="::/0"]] = 0) do={
            /ipv6 route add dst-address="::/0" blackhole distance=$blackholeDistance routing-table=$tName comment=$tag;
        };
    };
};
