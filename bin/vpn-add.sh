#!/bin/bash +x

source conf.sh

QUAGGA_PASSWORD="testpassword123"
HOSTNAME=`hostname`

curl="curl --retry 3 --silent --show-error --fail"
instance_metadata_url=http://169.254.169.254/latest/meta-data
ox='ip netns exec openswan'

# Wait until meta-data is available.
perl -MIO::Socket::INET -e '
 until(new IO::Socket::INET("169.254.169.254:80")){print"Waiting for meta-data...\n";sleep 1}
     ' | $logger

INSTANCE_IP=`$curl -s $instance_metadata_url/local-ipv4`

  #create ipsec config files

  cat <<EOF > /etc/ipsec.d/${VPNID}.conf
conn ${VPNID}-1
        authby=secret
        auto=start
        left=$NAMESPACE_TUNNEL1_IP
        leftid=$NAMESPACE_TUNNEL1_IP
        right=$VGW_TUNNEL1_OUTSIDE_IP
        rightid=$VGW_TUNNEL1_OUTSIDE_IP
        type=tunnel
        ikelifetime=8h
        keylife=1h
        phase2alg=aes128-sha1;modp1024
        ike=aes128-sha1
        auth=esp
        keyingtries=%forever
        aggrmode=no
        keyexchange=ike
        ikev2=never
        leftsubnet=$VGW_TUNNEL1_INSIDE_IP/30
        rightsubnet=0.0.0.0/0
        dpddelay=10
        dpdtimeout=30
        dpdaction=restart_by_peer

conn ${VPNID}-2
        authby=secret
        auto=start
        left=$NAMESPACE_TUNNEL2_IP
        leftid=$NAMESPACE_TUNNEL2_IP
        right=$VGW_TUNNEL2_OUTSIDE_IP
        rightid=$VGW_TUNNEL2_OUTSIDE_IP
        type=tunnel
        ikelifetime=8h
        keylife=1h
        phase2alg=aes128-sha1;modp1024
        ike=aes128-sha1
        auth=esp
        keyingtries=%forever
        aggrmode=no
        keyexchange=ike
        ikev2=never
        leftsubnet=$VGW_TUNNEL2_INSIDE_IP/30
        rightsubnet=0.0.0.0/0
        dpddelay=10
        dpdtimeout=30
        dpdaction=restart_by_peer
EOF

  chmod 644 /etc/ipsec.d/${VPNID}.conf


  cat <<EOF > /etc/ipsec.d/${VPNID}-1.secrets
$NAMESPACE_TUNNEL1_IP $VGW_TUNNEL1_OUTSIDE_IP: PSK "$TUNNEL1_SECRET"
EOF

  chmod 644 /etc/ipsec.d/${VPNID}-1.secrets

  cat <<EOF > /etc/ipsec.d/${VPNID}-2.secrets
$NAMESPACE_TUNNEL2_IP $VGW_TUNNEL2_OUTSIDE_IP: PSK "$TUNNEL2_SECRET"
EOF

  chmod 644 /etc/ipsec.d/${VPNID}-2.secrets

    #Setup BGP
  cat <<EOF >> /etc/quagga/bgpd.conf
router bgp $CUSTOMER_ASN
    neighbor $VGW_TUNNEL1_INSIDE_IP remote-as $AWS_ASN
    neighbor $VGW_TUNNEL1_INSIDE_IP description ${VPNID}-1
    neighbor $VGW_TUNNEL2_INSIDE_IP remote-as $AWS_ASN 
    neighbor $VGW_TUNNEL2_INSIDE_IP description ${VPNID}-2
EOF

  $ox ip addr add dev eth0 $NAMESPACE_TUNNEL1_IP/28
  $ox ip addr add dev eth0 $NAMESPACE_TUNNEL2_IP/28
  $ox ip addr add dev eth0 $CGW_TUNNEL1_INSIDE_IP/30
  $ox ip addr add dev eth0 $CGW_TUNNEL2_INSIDE_IP/30

  #Configure routing
  iptables -t nat -D PREROUTING -s $VGW_TUNNEL1_OUTSIDE_IP/32 -i eth0 -j DNAT --to-destination $NAMESPACE_TUNNEL1_IP
  iptables -t nat -A PREROUTING -s $VGW_TUNNEL1_OUTSIDE_IP/32 -i eth0 -j DNAT --to-destination $NAMESPACE_TUNNEL1_IP
  iptables -t nat -D POSTROUTING -d $VGW_TUNNEL1_OUTSIDE_IP/32 -j SNAT --to-source $INSTANCE_IP
  iptables -t nat -A POSTROUTING -d $VGW_TUNNEL1_OUTSIDE_IP/32 -j SNAT --to-source $INSTANCE_IP 

  iptables -t nat -D PREROUTING -s $VGW_TUNNEL2_OUTSIDE_IP/32 -i eth0 -j DNAT --to-destination $NAMESPACE_TUNNEL2_IP
  iptables -t nat -A PREROUTING -s $VGW_TUNNEL2_OUTSIDE_IP/32 -i eth0 -j DNAT --to-destination $NAMESPACE_TUNNEL2_IP
  iptables -t nat -D POSTROUTING -d $VGW_TUNNEL2_OUTSIDE_IP/32 -j SNAT --to-source $INSTANCE_IP
  iptables -t nat -A POSTROUTING -d $VGW_TUNNEL2_OUTSIDE_IP/32 -j SNAT --to-source $INSTANCE_IP 
