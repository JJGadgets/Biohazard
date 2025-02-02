curl -vk -H "Authorization: Bearer $FGT_API_KEY" 'https://$FGT_HOST/api/v2/monitor/system/dhcp?ipv6=true&vdom=root'
curl -vk -H "Authorization: Bearer $FGT_API_KEY" 'https://$FGT_HOST/api/v2/cmdb/system/dns-database/test.internal' -X PUT --json '{"dns-entry":[{"id":1,"status":"enable","ttl":0,"preference":10,"hostname":"edns","ip":"10.2.3.4","type":"A"}]}'
