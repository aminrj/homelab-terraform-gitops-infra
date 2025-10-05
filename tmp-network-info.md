root@proxmox-node-5:~# cat /etc/network/interfaces
auto lo
iface lo inet loopback

iface enp89s0 inet manual

iface wlo1 inet manual

auto vmbr2
iface vmbr2 inet manual
bridge-ports enp89s0
bridge-stp off
bridge-fd 0
bridge-vlan-aware yes
bridge-vids 10-100 90

# VLAN 90 for proxmox cluster communication

auto vmbr2.90
iface vmbr2.90 inet static
address 10.0.0.5/24
gateway 10.0.0.1

source /etc/network/interfaces.d/\*
root@proxmox-node-5:~#
