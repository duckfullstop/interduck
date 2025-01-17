+++
title = "Solaredge Inverter sporadic packet loss fix"
subtitle = "A quick fix for those of you suffering with packet loss to Solaredge Home Hub inverters."
date = "2025-01-17T15:00:00+00:00"
slug = "solaredge_eee"
+++

Just a quick one this time: if you find yourself having issues when connecting a _SolarEdge Home Hub Inverter_ to your network, there's an extraordinarily silly Layer 1 issue that might be affecting you, **especially if you use a managed or PoE switch.**

Some of the symptoms I've observed:
* inverter fails to get a DHCP lease
* inverter gets a DHCP lease, but can't connect to the monitoring server / monitoring data (S_OK) shows failed
* local modbus over IP / Home Assistant connections are unreliable


To find out if this might be your problem, simply try pinging your inverter `ping -t 192.168.1.10` (replace 192.168.1.10 with the address of your inverter).

A healthy connection would exhibit no loss, like so:
```
64 bytes from 192.168.1.10: icmp_seq=0 ttl=64 time=12.032 ms
64 bytes from 192.168.1.10: icmp_seq=1 ttl=64 time=2.637 ms
64 bytes from 192.168.1.10: icmp_seq=2 ttl=64 time=2.491 ms
64 bytes from 192.168.1.10: icmp_seq=3 ttl=64 time=4.291 ms
64 bytes from 192.168.1.10: icmp_seq=4 ttl=64 time=1.985 ms
64 bytes from 192.168.1.10: icmp_seq=5 ttl=64 time=5.039 ms
64 bytes from 192.168.1.10: icmp_seq=6 ttl=64 time=10.535 ms
64 bytes from 192.168.1.10: icmp_seq=7 ttl=64 time=2.771 ms
64 bytes from 192.168.1.10: icmp_seq=8 ttl=64 time=5.647 ms
64 bytes from 192.168.1.10: icmp_seq=9 ttl=64 time=4.436 ms
```

A connection with sporadic packet loss would look something like this:
```
64 bytes from 192.168.1.10: icmp_seq=0 ttl=64 time=12.032 ms
64 bytes from 192.168.1.10: icmp_seq=1 ttl=64 time=2.637 ms
Request timeout for icmp_seq 2
Request timeout for icmp_seq 3
64 bytes from 192.168.1.10: icmp_seq=4 ttl=64 time=1.985 ms
64 bytes from 192.168.1.10: icmp_seq=5 ttl=64 time=5.039 ms
Request timeout for icmp_seq 6
64 bytes from 192.168.1.10: icmp_seq=7 ttl=64 time=2.771 ms
64 bytes from 192.168.1.10: icmp_seq=8 ttl=64 time=1529.647 ms
64 bytes from 192.168.1.10: icmp_seq=9 ttl=64 time=4.436 ms
```
If you're seeing this, **try turning off Energy-Efficient Ethernet on the switch port connected to your inverter.** You might find this referred to by one of several things, depending on the manufacturer - these include _EEE_ and _802.3az_. On some PoE switches (including Ubiquiti brand), try turning PoE off on that port - on others, you can specifically disable the feature.

### Technical BS

I'm not entirely sure why this fixes the issue - I can only theorise that the ethernet chipset in use on the inverter is not waking up in time after receiving a standard IDLE packet, after a period of LPI (Low-Power Idle). I don't have any gear for working with the physical layer of Ethernet, so this is pure speculation.

Wikipedia has the following to say:
> When the controlling software or firmware decides that no data needs to be sent, it can issue a low-power idle (LPI) request to the Ethernet controller physical layer PHY. The PHY will then send LPI symbols for a specified time onto the link, and then disable its transmitter. Refresh signals are sent periodically to maintain link signaling integrity. When there is data to transmit, a normal IDLE signal is sent for a predetermined period of time. The data link is considered to be always operational, as the receive signal circuit remains active even when the transmit path is in sleep mode.