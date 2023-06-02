#!/bin/bash

# This script doesn't work anymore by adding it to the ddns_provider.conf
# instead it can be used in a job with the required parameters in a cronjob

# from /etc/ddns_provider.conf01
# Input:
#    1. DynDNS style request:
#       modulepath = DynDNS
#       queryurl = [Update URL]?[Query Parameters]
#
#    2. Self-defined module:
#       modulepath = /sbin/xxxddns
#       queryurl = DDNS_Provider_Name
#
#       Our service will assign parameters in the following order when calling module:
#           ($1=username, $2=password, $3=hostname, $4=ip)
#
# Output:
#    When you write your own module, you can use the following words to tell user what happen by print it.
#    You can use your own message, but there is no multiple-language support.
#
#       good -  Update successfully.
#       nochg - Update successfully but the IP address have not changed.
#       nohost - The hostname specified does not exist in this user account.
#       abuse - The hostname specified is blocked for update abuse.
#       notfqdn - The hostname specified is not a fully-qualified domain name.
#       badauth - Authenticate failed.
#       911 - There is a problem or scheduled maintenance on provider side
#       badagent - The user agent sent bad request(like HTTP method/parameters is not permitted)
#       badresolv - Failed to connect to  because failed to resolve provider address.
#       badconn - Failed to connect to provider because connection timeout.
#

set -e;
#set -x; # enable debug output

# define external interface like eth0 or so which is used for ipv6
INTERFACE="ovs_eth0"

ipv4Regex="((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])"
ipv6Regex="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"
ipv6="true"
# disable ipv4 because of DS-LITE, if you have an IPV4 enable it
ipv4="true"

#set time to life
ttl="300"

# proxy="true" 
# ask for existing proxy, don't override it <.<

# DSM Config
username="$1"
password="$2"
hostname="$3"
ipAddr="$4"

# DNS Recordtypes
recordType="A" 		#IPV4
recordTypev6="AAAA" #IPV6

# Cloudflare API-Calls for listing entries
listDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records?type=${recordType}&name=${hostname}"
# above only, if IPv4 and/or IPv6 is provided
listDnsv6Api="https://api.cloudflare.com/client/v4/zones/${username}/dns_records?type=${recordTypev6}&name=${hostname}" # if only IPv4 is provided

#Fetch and filter IPv6, if Synology won't provide it, ignore localhost and local addresses
if [[ $ipv6 = "true" ]]; then
	ip6fetch=$(/sbin/ip -6 addr show ${INTERFACE} | grep -oP "$ipv6Regex" | egrep -v "(^::1)|(^fe80)|(^fd00)")
	ip6Addr=$(if [ -z "$ip6fetch" ]; then echo ""; else echo "${ip6fetch:0:$((${#ip6fetch}))}"; fi) # in case of NULL, echo NULL

	if [[ -z "$ip6Addr" ]]; then
		ipv6="false"; 	# no external ipv6 for $INTERFACE is available
	fi
fi

if [[ $ipv4 = "true" ]]; then
	
	#test if a ipv4 was provided
	if [[ ! $variable ]]; then
		ipAddr=$(ddnsd -e |cut -d "=" -f2 | tr -d " ")
	fi

	# test if ipv4 is valid
	if [[ ! $ipAddr =~ $ipv4Regex ]]; then
		ipv4="false";		# IPV4 is invalid
	fi

	res=$(curl -s -X GET "$listDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json")
	resSuccess=$(echo "$res" | jq -r ".success")
	if [[ $resSuccess != "true" ]]; then
		echo "badauth";
		exit 1;
	fi

	recordId=$(echo "$res" | jq -r ".result[0].id")
	recordIp=$(echo "$res" | jq -r ".result[0].content")
	recordProx=$(echo "$res" | jq -r ".result[0].proxied")
	recordTtl=$(echo "$res" | jq -r ".result[0].ttl")
fi

if [[ $ipv6 = "true" ]]; then ## Adding new commands, if Synology didn't provided IPv6
	resv6=$(curl -s -X GET "$listDnsv6Api" -H "Authorization: Bearer $password" -H "Content-Type:application/json");
	resSuccess=$(echo "$resv6" | jq -r ".success")

	if [[ $resSuccess != "true" ]]; then
		echo "badauth";
		exit 1;
	fi

	recordIdv6=$(echo "$resv6" | jq -r ".result[0].id");
	recordIpv6=$(echo "$resv6" | jq -r ".result[0].content");
	recordProxv6=$(echo "$resv6" | jq -r ".result[0].proxied");
	recordTtlv6=$(echo "$res" | jq -r ".result[0].ttl");
fi

# API-Calls for creating DNS-Entries
createDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records" # does also work for IPv6


# API-Calls for update DNS-Entries
updateDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records/${recordId}" 		# for IPv4
update6DnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records/${recordIdv6}" 	# for IPv6

if [[ $recordIp = "$ipAddr" ]] && [[ $recordIpv6 = "$ip6Addr" ]]; then
    echo "nochg"; #nochg - Update successfully but the IP address have not changed.
    exit 0;
fi

# update ipv4 if it's enabled
if [[ $ipv4 = "true" ]] ; then
	if [[ $recordId = "null" ]]; then
        # Record does not exists
		proxy="true" # new Record. Enable proxy by default
		res=$(curl -s -X POST "$createDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"$recordType\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":$proxy,\"ttl\":$ttl}")
	else
		# Record exists
		res=$(curl -s -X PUT "$updateDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"$recordType\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":$recordProx,\"ttl\":$recordTtl}")
	fi
fi

if [[ $ipv6 = "true" ]] ; then
	if [[ $recordIdv6 = "null" ]]; then
	# IPv6 Record does not exist
	proxy="true"; # new entry, enable proxy by default
    res6=$(curl -s -X POST "$createDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"$recordTypev6\",\"name\":\"$hostname\",\"content\":\"$ip6Addr\",\"proxied\":$proxy,\"ttl\":$ttl}");
	else
    # IPv6 Record exists
    res6=$(curl -s -X PUT "$update6DnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"$recordTypev6\",\"name\":\"$hostname\",\"content\":\"$ip6Addr\",\"proxied\":$recordProxv6,\"ttl\":$recordTtlv6}");
	fi;
	res6Success=$(echo "$res6" | jq -r ".success");
fi
resSuccess=$(echo "$res" | jq -r ".success")

if [[ $resSuccess = "true" ]] || [[ $res6Success = "true" ]]; then
    echo "good";
else
    echo "badauth";
fi
