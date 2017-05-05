#! /usr/bin/python
import boto3
import json
import xml.etree.ElementTree as ET
import os 
#from boto.vpc import VPCConnection

#s = boto3.session.Session(profile_name='default')
#print s
import urllib2
publicIP = urllib2.urlopen('http://169.254.169.254/latest/meta-data/public-ipv4').read()

# get tags of my own instance

directory = "/opt/beergp"
if not os.path.exists(directory):
    os.makedirs(directory)

allocated_ips = []
prev_ip_assignments = {}
new_ip_assignments = {}

filename = "%s/ip_allocs" % directory
f = open(filename, "w+")
for line in f:
    vpn_id, ip0, ip1 = line.split(',') 
    prev_ip_assignments[vpn_id] = [ip0,ip1]
    allocated_ips += [ip0, ip1]
f.close()

def allocate_new_ips(allocated_ips):
    ips = []
    i = 2
    while i < 4000000 and len(ips) < 2:
        if i not in allocated_ips:
            ips.append(i)
        i += 1

    if len(ips) < 2:
        # TODO: handle this
        print "Could not allocate any new ips"
        return []
    return ips
        

ec2 = boto3.client("ec2")
vpns = ec2.describe_vpn_connections()
records = []
for vpn in vpns["VpnConnections"]:
    cgc = vpn['CustomerGatewayConfiguration']
    x = ET.fromstring(cgc)
    vpn_id = x.attrib["id"]
    tunnels = x.findall("ipsec_tunnel")
    cgw_ip = ""
    if not len(tunnels):
        print "No tunnels found for vpn_id %s, skipping" % vpn_id

    cgw_ip = tunnels[0].find("customer_gateway/tunnel_outside_address/ip_address").text
    if cgw_ip != publicIP:
        print "VPN %s with cgw_ip %s does not target this CGW (%s), skipping" % (vpn_id, cgw_ip, publicIP)
        continue

    ips = []
    if vpn_id in prev_ip_assignments:
        # maintain the same ip assignment 
        ips = prev_ip_assignments[vpn_id]
    else:
        ips = allocate_new_ips(allocated_ips)
        if not ips:
            # Skip of no ips were allocated
            continue 
        allocated_ips += ips

    new_ip_assignments[vpn_id] = ips

    i = 0 
    r = {}
    for t in tunnels:
        print "processing tunnel %d" % i 
        print ET.tostring(t)
        i += 1
        prefix = "tunnel%d_" % i
        r[prefix + "cgw_inside_address"] = t.find("customer_gateway/tunnel_inside_address/ip_address").text
        r[prefix + "cgw_outside_address"] = t.find("customer_gateway/tunnel_outside_address/ip_address").text
        r[prefix + "vgw_inside_address"] = t.find("vpn_gateway/tunnel_inside_address/ip_address").text
        r[prefix + "vgw_inside_address"] = t.find("vpn_gateway/tunnel_inside_address/ip_address").text
        r[prefix + "secret"] = t.find("ike/pre_shared_key").text

    records.append(r)

f = open(filename, 'w')    
for vpn_id, ips in new_ip_assignments.iteritems():
    f.write("%s,%s,%s" % (vpn_id, ips[0], ips[1]))
f.close()


print "Exporting Records"
for r in records:
    print r